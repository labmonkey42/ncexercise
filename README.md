The Start-Exercise.ps1 PowerShell script in this repository reserves and provisions a new Amazon EC2 t2.micro Ubuntu 16.04 LTS instance running nginx with an example static index.html page.

This script assumes the following about the host on which it is run:
+ AWS CLI and AWS PowerShell Tools are installed.
+ AWS CLI is logged in to an appropriate account.
+ AWS CLI/PowerShell Tools has a default region set. (e.g. Set-DefaultAWSRegion)
+ ssh-keygen is present.
+ The key specified by $env:AWS_KEY_NAME either does not yet exist in the EC2 region, or exists in the same folder as this script with the filename <AWS_KEY_NAME>.pem - Note that if the key exists in the region but the private key file in this directory is not present, this script will remove the EC2 KeyPair and create a new one since Amazon does not store the private key.  A better way to do this would be to fail early when the private key is not present, alert the user to this issue, and let them supply the private key in the appropriate location.
