Trample is a tool for quickly enumerating AWS Organizations and their accounts recursively.
It is written in bash and uses the AWS CLI to enumerate the accounts.
Firstly it will use a privileged account to enumerate the accounts and then assume the OrganizationAccountAccessRole or a specific role for each account to enumerate the accounts recursively.
results are saved to a file and can be resumed from the same file.
each resource is saved in the format of a json object that is named: OrganizationID_OUNameAccountID_ResourceType.json
Trample is a tool for quickly enumerating AWS Organizations and their accounts recursively.
It is written in bash and uses the AWS CLI to enumerate the accounts.
Firstly it will use a privileged account to enumerate the accounts and then assume the OrganizationAccountAccessRole or a specific role for each account to enumerate the accounts recursively.
Results are saved to a file and can be resumed from the same file.
Each resource is saved in the format of a json object that is named: OrganizationID_OUNameAccountID_ResourceType.json

## Usage

1. Ensure you have AWS CLI installed and configured with credentials that have access to AWS Organizations.
2. Make the script executable:
   ```bash
   chmod +x trample.sh
   ```
3. Run the script:
   ```bash
   ./trample.sh
   ```

Optional parameters:
- `-r, --role`: Specify a custom role to assume (default: OrganizationAccountAccessRole)
- `-o, --output`: Specify output directory (default: trample_results)
- `--resume`: Resume from a previous scan file

Example:
```bash
# Basic usage with default settings
./trample.sh

# Using a custom role
./trample.sh -r CustomAuditRole

# Specify a different output directory
./trample.sh -o /path/to/custom/output

# Resume a previous scan
./trample.sh --resume /path/to/trample_results/previous_scan.json

# Combine options
./trample.sh -r CustomAuditRole -o /path/to/custom/output

# Full example with all options
./trample.sh \
    --role CustomAuditRole \
    --output /path/to/results \
    --resume /path/to/previous_scan.json
```
