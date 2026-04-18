Malware Scanner for Ubuntu Server - Usage Instructions
Overview
This malware scanner is designed to detect malicious files and suspicious patterns across various file types including scripts, Docker files, Terraform configurations, and source code. It uses multiple detection methods including signature matching, pattern recognition, and heuristic analysis.

Installation
Prerequisites
Ubuntu Server (tested on 20.04 LTS and 22.04 LTS)

GCC compiler

OpenSSL development libraries

Root/sudo access (for complete system scanning)

Installation Steps
Install dependencies:

bash
sudo apt update
sudo apt install g++ libssl-dev
Download the scanner:

bash
wget https://example.com/malware_scanner.cpp -O malware_scanner.cpp
Compile the program:

bash
g++ -std=c++17 -o malware_scanner malware_scanner.cpp -lcrypto
Set up the malware signature database:

bash
touch malware_signatures.db
# Add known malware MD5 hashes to this file (one per line)
Set up logging:

bash
sudo mkdir -p /var/log/
sudo touch /var/log/malware_scanner.log
sudo chmod 644 /var/log/malware_scanner.log
Configuration
File Types to Scan
The scanner is configured by default to scan these file extensions:

Scripts: .sh, .php, .py, .pl, .js, .cgi

Configuration files: .yml, .yaml, .json, .tf (Terraform)

Docker files: Dockerfile, .dockerfile

Binaries: .so, .bin

All files (no extension)

To modify the file types:

Edit the SCAN_FILE_TYPES set in the source code

Recompile the program

Scan Directories
Default scan directories include:

System binaries: /bin, /sbin, /usr/bin, /usr/sbin, /usr/local/bin

Temporary directories: /tmp

Web directories: /var/www

To add more directories:

Edit the SCAN_DIRECTORIES array in the source code

Recompile the program

Usage
Basic Scan
bash
sudo ./malware_scanner
This will scan all configured directories and log results to /var/log/malware_scanner.log

Scanning Specific File Types
The scanner can detect malicious patterns in:

Scripts (Bash, Python, Perl, PHP, JavaScript):

Detects dangerous functions like eval(), exec(), system()

Finds suspicious commands like wget, curl, nc in scripts

Checks for obfuscated code patterns

Docker files:

Detects suspicious base images

Finds dangerous commands in RUN instructions

Checks for exposed ports and privileged mode

Terraform configurations:

Detects overly permissive security groups

Finds suspicious IAM policies

Checks for hardcoded credentials

Source code (C, C++, Java, etc.):

Detects known vulnerable functions

Finds suspicious system calls

Checks for potential buffer overflow patterns

Custom Directory Scan
To scan a specific directory (e.g., your project directory):

bash
sudo ./malware_scanner /path/to/your/directory
(Note: You'll need to modify the source code to accept command-line arguments for this)

Viewing Results
Check the log file for findings:

bash
sudo tail -f /var/log/malware_scanner.log
Sample log output:

text
2023-11-15 14:30:45 - Scanning directory: /var/www
2023-11-15 14:31:02 - Suspicious pattern found in /var/www/html/upload.php at line 42: eval(
2023-11-15 14:31:15 - Executable file detected: /tmp/.hidden_script.sh
Advanced Usage
Updating Malware Signatures
Add new MD5 hashes to malware_signatures.db

Hashes should be in lowercase, one per line

No need to recompile after updating signatures

Scheduling Regular Scans
Add to cron for daily scans:

bash
sudo crontab -e
Add this line:

text
0 2 * * * /path/to/malware_scanner
This will run the scan daily at 2 AM.

Integrating with CI/CD
To scan your Docker/Terraform files in a pipeline:

Add the scanner to your build environment

Run it against your project directory

Fail the build if any threats are detected

Example for GitLab CI:

yaml
security_scan:
  stage: test
  script:
    - g++ -std=c++17 -o malware_scanner malware_scanner.cpp -lcrypto
    - ./malware_scanner ${CI_PROJECT_DIR} | tee scan.log
    - ! grep -q "detected" scan.log
Limitations
Not a real-time scanner (run periodically)

Requires manual signature updates

May produce false positives (review logs)

Doesn't automatically quarantine files

Recommendations
Combine with other security tools like:

ClamAV for virus detection

rkhunter for rootkit detection

Lynis for system hardening

For Docker images:

Use docker scan (built-in vulnerability scanning)

Consider Trivy or Anchore for more comprehensive scanning

For Terraform:

Use tfsec or Checkov for IaC-specific scanning

Keep the scanner updated with new patterns and signatures

Troubleshooting
Problem: Permission denied errors
Solution: Run with sudo or adjust file permissions

Problem: Missing OpenSSL library
Solution: Install with sudo apt install libssl-dev

Problem: No findings in log
Solution: Check if scanned directories contain files with the configured extensions

Problem: False positives
Solution: Review and adjust the MALICIOUS_PATTERNS list in the source code