$ErrorActionPreference = "SilentlyContinue"

$securityGroup = Get-EC2SecurityGroup -GroupName "ncadminAccessSecurityGroup"
If ($securityGroup -eq $null) {
    # Discover local external IP address:
    $Response = Invoke-WebRequest "http://checkip.amazonaws.com/"
    $myIp = (($Response.Content | ForEach-Object {[char]$_}) -join '').trim()

    # Create a SecurityGroup on the default VPC for access to instances:
    $defaultVpcId = (Get-EC2AccountAttributes -AttributeName "default-vpc").AttributeValues[0].AttributeValue
    $securityGroupId = New-EC2SecurityGroup `
        -VpcId $defaultVpcId `
        -GroupName "ncadminAccessSecurityGroup" `
        -GroupDescription "SecurityGroup for ncadmin access to EC2 instance."
    $securityGroup = Get-EC2SecurityGroup -GroupId $securityGroupID
} Else {
    $securityGroupId = $securityGroup.GroupId
}

$sshRules = (
    $securityGroup.IpPermissions | `
    Where-Object { 
        $_.FromPort -eq 22 -and `
        $_.ToPort -eq 22 -and `
        $_.IpProtocol -eq "tcp" -and `
        (($_.IpRanges | Where-Object {$_ -eq "$myIp/32"}).Count -gt 0)
    }
)
If ($sshRules.Count -lt 1) {
    # Add SSH access to the SecurityGroup:
    $permission = New-Object Amazon.EC2.Model.IpPermission
    $permission.FromPort = 22
    $permission.ToPort = 22
    $permission.IpProtocol = "tcp"
    $permission.IpRanges.Add("$myIp/32")
    Grant-EC2SecurityGroupIngress `
        -GroupId $securityGroupId `
        -IpPermissions $permission
}
$webRules = (
    # Add HTTP access to the SecurityGroup:
    $securityGroup.IpPermissions | `
    Where-Object { 
        $_.FromPort -eq 22 -and `
        $_.ToPort -eq 22 -and `
        $_.IpProtocol -eq "tcp" -and `
        (($_.IpRanges | Where-Object {$_ -eq "$myIp/32"}).Count -gt 0)
    }
)
If ($webRules.Count -lt 1) {
    $permission = New-Object Amazon.EC2.Model.IpPermission
    $permission.FromPort = 80
    $permission.ToPort = 80
    $permission.IpProtocol = "tcp"
    $permission.IpRanges.Add("$myIp/32")
    Grant-EC2SecurityGroupIngress `
        -GroupId $securityGroupId `
        -IpPermissions $permission
}

If (Test-Path env:AWS_KEY_NAME) {
    # Use key file from environment if present.
    $ncadminKeyFile = $env:AWS_KEY_NAME
} Else {
    # Use key file in script location if not in environment.
    $ncadminKeyFile = [System.IO.Path]::Combine(
        $PSScriptRoot,
        "ncadminKeyPair.pem"
    )
}
If (not (Test-Path $ncadminKeyFile)) {
    # Key file not found; create it.
    $ncadminKeyPair = Get-EC2KeyPair -KeyName ncadminKeyPair
    If ($ncadminKeyPair -eq $null) {
        # KeyPair does not exist in EC2.
        $ncadminKeyPair = New-EC2KeyPair -KeyName ncadminKeyPair
        $ncadminKeyPair.KeyMaterial | Out-File -Encoding ascii $ncadminKeyFile
    }
}
# Generate public key from private for ssh authorized_keys.
$ncadminPublicKey = Invoke-Expression -Command "ssh-keygen -y -f $ncadminKeyFile"

# Locate Ubuntu 16.04 LTS HVM AMI in the current region:
$amiFilters = New-Object -TypeName "System.Collections.Generic.List[Amazon.EC2.Model.Filter]"
$amiNameFilter = New-Object Amazon.EC2.Model.Filter `
    -Property @{
        Name = "name";
        Value = "ubuntu/images/hvm-ssd/ubuntu-xenial-16.04-amd64-server-*"
    }
$amiFilters.Add($amiNameFilter)
$canonical = "099720109477"
$amis = Get-EC2Image `
    -Owner $canonical `
    -Filters $amiFilters `
    -Region ((Get-DefaultAWSRegion).Region)
$ami = ($amis | Sort-Object CreationDate -Descending)[0]

# Configure provisioning:
$provisioningData = @"
#cloud-config
packages:
  - nginx

users:
  - name: ncadmin
    groups: [ wheel ]
    sudo: [ "ALL=(ALL) NOPASSWD:ALL" ]
    shell: /bin/bash
    ssh-authorized-keys:
      - $ncadminPublicKey

write_files:
  - path: /var/www/html/index.html
    owner: www-data:www-data
    permissions: "0644"
    content: |
      <!DOCTYPE html>
      <head>
      <title>NewClassrooms Cloud Infrastructure Engineer Trial - Chris Lee</title>
      </head>
      <html>
      <body>
      <p>Hello, NewClassrooms.</p>
      </body>
      </html>

runcmd:
  - systemctl enable nginx
  - systemctl start nginx

"@
$userData = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($provisioningData))

# Reserve an instance:
$instanceReservation = New-EC2Instance `
    -ImageId $ami.ImageId `
    -InstanceType t2.micro `
    -KeyName ncadminKeyPair `
    -MaxCount 1 `
    -MinCount 1 `
    -SecurityGroupId $securityGroupId `
    -UserData $userData
$reservations = New-Object -TypeName "System.Collections.Generic.List[string]"
$reservations.Add($instanceReservation.ReservationId)
$reservationFilter = New-Object Amazon.EC2.Model.Filter `
    -Property @{
        Name = "reservation-id";
        Values = $reservations
    }
$instance = (Get-EC2Instance -Filter $reservationFilter).Instances[0]

while ([String]::IsNullOrWhiteSpace($instance.PublicIpAddress) -or [String]::IsNullOrWhiteSpace($instance.PublicDnsName)) {
    Start-Sleep -Milliseconds 20
    $instance = (Get-EC2Instance -Filter $reservationFilter).Instances[0]
}

# Report to user:
Write-Output "A new instance has started provisioning."
Write-Output "This instanced can be accessed with the following information:"
Write-Output "    URL: http://$($instance.PublicDnsName)/"
Write-Output "    SSH: $($instance.PublicDnsName)"
Write-Output "    SSK Key File: $ncadminKeyFile"
