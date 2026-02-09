# psenv - AWS Parameter Store to .env Tool

A Rust CLI tool that fetches secrets from AWS Parameter Store and generates `.env` files.

## Features

- Fetch environment variables from AWS Parameter Store
- Multiple merge strategies for existing `.env` files
- Template-based key discovery
- Dry-run mode for previewing changes
- Configurable logging and error handling

## Installation

From the project directory:

```bash
cargo build --release
```

The binary will be available at `target/release/psenv`.

## Usage

```bash
psenv --template .env.example --prefix "/studio-dev/" --output .env
```

### Required Arguments

- `--template` / `-t`: Template file path (e.g., `.env.example`)
- `--prefix` / `-p`: Parameter Store prefix (must start with `/`, e.g., `/studio-dev/`)

### Optional Arguments

- `--output` / `-o`: Output file (default: `.env`)
- `--strategy` / `-s`: Processing strategy (default: `overwrite`)
  - `overwrite`: Completely overwrite the file with only the fetched values
  - `update`: Update existing values and add new ones while preserving file format
  - `error`: Error if output file exists
- `--ignore-keys` / `-i`: Skip these keys (comma-separated, e.g., `DB_HOST,DEBUG`)
- `--require-all`: All keys must exist in Parameter Store, otherwise error (default: true)
- `--region` / `-r`: AWS region
- `--profile`: AWS profile
- `--dry-run`: Preview mode - show what would be written without creating files
- `--quiet` / `-q`: Quiet mode
- `--verbose` / `-v`: Verbose logging
- `--show-secrets`: Show secrets in plaintext (default: mask sensitive values)

## Workflow

1. Read all keys from the template file
2. Filter out keys specified in `--ignore-keys`
3. Fetch `prefix + key` values from AWS Parameter Store
4. Merge/overwrite into output file based on strategy

## Exit Codes

- 0: Success
- 1: Invalid arguments
- 3: Missing required parameters (when `--require-all` is used)
- 4: Output file exists (when `--strategy=error`)

## Special Behavior

- **Parameter Store paths**: `prefix + key` (prefix is automatically removed when writing to `.env`)
  - Example: `/studio-dev/DB_HOST` → `.env` contains `DB_HOST=value`
- **Ignored keys**: Keys in `--ignore-keys` are not fetched from Parameter Store
- **Required validation**: When `--require-all` is used, ignored keys are not checked
- **Secret masking**: By default, sensitive environment variables (containing keywords like `password`, `secret`, `key`, `token`, etc.) are masked in dry-run output. Use `--show-secrets` to display them in plaintext.

## Examples

### Basic usage
```bash
psenv -t .env.example -p "/myapp/prod/"
```

### Dry run to preview changes
```bash
psenv -t .env.example -p "/myapp/prod/" --dry-run
```

### Overwrite with clean configuration
```bash
psenv -t .env.example -p "/myapp/prod/" -s overwrite
```

### Skip certain keys
```bash
psenv -t .env.example -p "/myapp/prod/" -i "LOCAL_DEBUG,DEV_MODE"
```

### Use specific AWS profile and region
```bash
psenv -t .env.example -p "/myapp/prod/" --profile production --region us-west-2
```

### Show secrets in plaintext during dry-run
```bash
psenv -t .env.example -p "/myapp/prod/" --dry-run --show-secrets
```

## Template File Format

The template file should contain environment variable declarations:

```env
# Database configuration
DB_HOST=localhost
DB_PORT=5432
DB_NAME=

# API Keys
API_KEY=
SECRET_KEY=

# Optional settings
DEBUG=false
```

Both uncommented and commented variable declarations are parsed. Comments and empty lines are ignored.

## Secret Masking

By default, `psenv` automatically detects and masks sensitive environment variables in dry-run output:

```bash
# Default behavior (secrets are masked)
psenv -t .env.example -p "/myapp/prod/" --dry-run
```

Output example:
```
API_KEY=****** (24 chars, hidden)
DATABASE_PASSWORD=****** (23 chars, hidden)
DEBUG=false
JWT_SECRET=****** (32 chars, hidden)
PORT=3000
```

```bash
# Show secrets in plaintext
psenv -t .env.example -p "/myapp/prod/" --dry-run --show-secrets
```

Output example:
```
API_KEY=sk_live_1234567890abcdef
DATABASE_PASSWORD=super_secret_db_pass123
DEBUG=false
JWT_SECRET=jwt_super_secret_key_for_signing
PORT=3000
```

### Sensitive Key Detection

The tool automatically detects keys containing these keywords (case-insensitive):
- `password`, `passwd`, `pwd`
- `secret`, `key`, `token`
- `auth`, `credential`, `cred`
- `private`, `secure`, `salt`
- `hash`, `signature`, `cert`, `certificate`