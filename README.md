The Start-Exercise.ps1 PowerShell script in this repository reserves and provisions a new Amazon EC2 t2.micro Ubuntu 16.04 LTS instance running nginx with an example static index.html page.

This script assumes the following about the host on which it is run:
+ AWS CLI and AWS PowerShell Tools are installed.
+ AWS CLI is logged in to an appropriate account.
+ AWS CLI/PowerShell Tools has a default region set. (e.g. Set-DefaultAWSRegion)
+ ssh-keygen is present.
