# Elisa Message Copy Verification System

**⚠️ ONE-TIME VERIFICATION TOOL**

This module provides tools for verifying and correcting Elisa message copies in `config/locales/elisa_es.yml` against the official KIRO_PROMPT_FLOWS_v5.md specification. This is a **one-time utility** designed to ensure message content matches the v5 specification exactly.

## Purpose

The message centralization work is complete — all message strings have been extracted from code to YAML, and all services now use `I18n.t()` lookups. However, this tool verifies that the actual message **text content** in the YAML file matches the official v5 specification.

**This is a content verification task** — NO changes to:
- YAML key names or structure
- I18n.t() calls in application code
- Business logic or service classes

Only the message text content within `elisa_es.yml` can be updated.

## Quick Start

### Dry-Run Mode (Analyze Only)

```bash
# Analyze messages and generate report without making changes
bundle exec ruby lib/elisa_verification/cli.rb

# With verbose output
bundle exec ruby lib/elisa_verification/cli.rb --verbose
```

### Apply Corrections

```bash
# Apply corrections to YAML file (creates backup first)
bundle exec ruby lib/elisa_verification/cli.rb --apply

# With custom paths
bundle exec ruby lib/elisa_verification/cli.rb \
  --yaml config/locales/elisa_es.yml \
  --spec ../KIRO_PROMPT_FLOWS_v5.md \
  --report .kiro/specs/elisa-message-copy-verification/verification-report.md \
  --apply
```

### Get Help

```bash
bundle exec ruby lib/elisa_verification/cli.rb --help
```

## Command-Line Options

| Option | Description | Default |
|--------|-------------|---------|
| `--yaml PATH` | Path to YAML file to verify | `config/locales/elisa_es.yml` |
| `--spec PATH` | Path to v5 specification | `../KIRO_PROMPT_FLOWS_v5.md` |
| `--report PATH` | Path to save report | `.kiro/specs/elisa-message-copy-verification/verification-report.md` |
| `--apply` | Apply corrections (default: dry-run) | `false` |
| `--skip-i18n` | Skip I18n validation (faster) | `false` |
| `--verbose` | Show detailed output | `false` |
| `--help` | Show help message | - |

## Expected Output

### Dry-Run Mode Output

```
=== Elisa Message Copy Verification ===

Configuration:
  YAML file: config/locales/elisa_es.yml
  Spec file: ../KIRO_PROMPT_FLOWS_v5.md
  Report: .kiro/specs/elisa-message-copy-verification/verification-report.md
  Apply corrections: NO (dry-run)
  Skip I18n validation: NO

📖 Loading V5 specification...
✓ Parsed 42 reference messages from ../KIRO_PROMPT_FLOWS_v5.md

📝 Loading YAML file...
✓ Loaded 77 message keys from config/locales/elisa_es.yml

🔍 Comparing messages...
✓ Analyzed 18 messages
  - 0 match v5 specification (0.0%)
  - 18 require corrections (100.0%)

⚠️  Warning: 13 message(s) skipped - no flow ID comment found
⚠️  Warning: 41 message(s) skipped - no v5 reference found

📊 Generating report...
✓ Report saved to .kiro/specs/elisa-message-copy-verification/verification-report.md

============================================================
VERIFICATION SUMMARY
============================================================

📋 Findings:
   - Total messages checked: 18
   - Messages matching v5: 0
   - Messages needing correction: 18

📄 Detailed report available at:
   .kiro/specs/elisa-message-copy-verification/verification-report.md

⚠️  DRY-RUN MODE
   No files have been modified.
   Review the report above, then run with --apply to make changes.
```

### Apply Mode Output

```
=== Elisa Message Copy Verification ===

[... same loading steps ...]

💾 Applying corrections...
✓ Created backup: config/locales/elisa_es.yml.backup.20260611054532
✓ Applied 18 corrections to YAML file

✅ Validating corrected YAML...
✓ YAML syntax valid
✓ I18n compatible
✓ All interpolation variables correct

💾 Saving corrected YAML...
✓ Saved to config/locales/elisa_es.yml

📊 Generating report...
✓ Report saved to verification-report.md

============================================================
VERIFICATION COMPLETE
============================================================

✅ All corrections applied successfully!
   - Backup: config/locales/elisa_es.yml.backup.20260611054532
   - Report: verification-report.md

Next steps:
   1. Review the verification report
   2. Run tests: bundle exec rspec spec/lib/elisa_verification/
   3. Verify I18n.t() calls still work correctly
```

## Error Handling

### Common Errors

**YAML File Not Found**
```
❌ ERROR: YAML file not found
   Path: config/locales/elisa_es.yml
   
   Please check the file path and try again.
```

**Spec File Not Found**
```
❌ ERROR: V5 spec file not found
   Path: ../KIRO_PROMPT_FLOWS_v5.md
   
   Please check the file path and try again.
```

**YAML Syntax Error**
```
❌ ERROR: YAML syntax error
   File: config/locales/elisa_es.yml
   Line 42: mapping values are not allowed here
   
   Please fix the YAML syntax and try again.
```

**I18n Validation Failure**
```
❌ ERROR: I18n validation failed
   Rails cannot load the corrected YAML file.
   
   Errors:
   - Duplicate key found: elisa.provider.onboarding.welcome
   
   The YAML file was NOT modified. Please fix these issues and try again.
```

### Warnings

**Missing Flow ID Comments**
```
⚠️  Warning: 13 message(s) skipped - no flow ID comment found:
   - es.elisa.provider.bio.question_1
   - es.elisa.provider.bio.question_2
   [... more keys ...]
   
   These messages cannot be verified without flow ID comments.
```

**No V5 Reference Found**
```
⚠️  Warning: 41 message(s) skipped - no v5 reference found:
   - es.elisa.provider.onboarding.welcome (P1A)
   - es.elisa.provider.onboarding.name_prompt (P2A)
   [... more keys ...]
   
   The v5 spec does not define reference messages for these flow IDs.
```

## Components

### YamlValidator

The `YamlValidator` class validates YAML files for:
1. **Syntax correctness** - Can the YAML be parsed?
2. **Rails I18n compatibility** - Can Rails load the translations?
3. **Interpolation variable syntax** - Are variables using correct Rails format?

#### Usage

```ruby
require 'elisa_verification/yaml_validator'

# Initialize with YAML file path
validator = ElisaVerification::YamlValidator.new('config/locales/elisa_es.yml')

# Validate YAML syntax only
result = validator.validate_syntax
if result.valid?
  puts "YAML syntax is valid!"
else
  puts "Errors found:"
  result.errors.each { |error| puts "  - #{error}" }
end

# Validate interpolation syntax
result = validator.validate_interpolation
# Returns ValidationResult with errors for incorrect variable syntax

# Validate I18n compatibility (requires Rails environment)
result = validator.validate_i18n
# Executes rails runner to check if Rails can load translations

# Run all validations at once
result = validator.validate_all
if result.valid?
  puts "All validations passed! ✅"
else
  puts "Validation failed with #{result.errors.size} errors:"
  result.errors.each { |error| puts "  - #{error}" }
end
```

#### Validation Methods

**validate_syntax**
- Uses Ruby's YAML.load_file to parse the file
- Catches Psych::SyntaxError and reports line numbers
- Returns ValidationResult with parsing errors

**validate_interpolation**
- Checks that all interpolation variables use Rails syntax: `%{var}`
- Detects common incorrect patterns:
  - Mustache/Handlebars: `{{var}}`
  - JavaScript/Shell: `${var}`
  - Printf: `%s`, `%d`
  - Python: `{var}`
- Validates variable names (letters, numbers, underscores only)
- Detects malformed variables (spaces, dashes, special characters)
- Detects unescaped `%` characters

**validate_i18n**
- Executes `rails runner "I18n.backend.load_translations"`
- Captures output and detects:
  - Loading errors
  - Duplicate keys
  - Missing translations
  - Conflicting key definitions
- Returns ValidationResult with I18n-specific errors

**validate_all**
- Runs syntax validation first (early return if fails)
- Then runs interpolation validation
- Finally runs I18n validation
- Returns combined ValidationResult with all errors

#### Key Features

1. **Line Number Reporting**: All errors include line numbers for easy debugging
2. **Multiple Error Detection**: Finds all issues in one pass
3. **Rails Integration**: Uses rails runner for accurate I18n validation
4. **Comprehensive Checks**: Validates syntax, interpolation, and I18n compatibility

#### Error Examples

**Syntax Errors**
```
Line 42: mapping values are not allowed here
```

**Interpolation Errors**
```
Line 15: Mustache-style interpolation {{name}} should be %{name}
Line 22: Interpolation variable %{user-name} contains dashes - use underscores
Line 35: Unescaped % character detected - use %% to escape or %{var} for interpolation
```

**I18n Errors**
```
Rails I18n validation failed: duplicate key found in YAML
I18n detected missing translation keys
```

### MessageCorrector

The `MessageCorrector` class applies corrections to YAML messages while preserving:
- File structure and indentation
- Comments (flow IDs, variable docs, section headers)
- Blank lines
- UTF-8 encoding (emojis, Spanish special characters)

#### Usage

```ruby
require 'elisa_verification/message_corrector'

# Initialize with YAML file path
corrector = ElisaVerification::MessageCorrector.new(
  'config/locales/elisa_es.yml',
  preserve_comments: true
)

# Apply a correction to a simple string value
corrector.apply_correction(
  'elisa.provider.onboarding.welcome',
  '¡Hola! 👋 Soy Elisa de Trato. Te voy a ayudar a crear tu perfil de técnico.'
)

# Apply a correction to an array value
corrector.apply_correction(
  'elisa.provider.list_messages.decline_reasons',
  ['Opción 1', 'Opción 2', 'Opción 3']
)

# Save to a new file
corrector.save('config/locales/elisa_es_corrected.yml')

# Or get the content as a string
yaml_content = corrector.to_yaml_string
```

#### Key Features

1. **Line-by-Line Processing**: Uses string manipulation instead of YAML AST to preserve formatting
2. **Comment Preservation**: Maintains all comments including flow IDs and variable documentation
3. **Intelligent Quoting**: Automatically determines when YAML values need to be quoted
4. **Interpolation Safety**: Preserves Rails interpolation variables (`%{name}`, `%{phone}`, etc.)
5. **UTF-8 Support**: Handles emojis and Spanish special characters correctly

#### Supported Value Types

- **String values**: Simple text messages with proper quoting when needed
- **Array values**: Lists like decline reasons, price ranges, experience levels
- **Hash values**: Not fully implemented (returns false)

#### Technical Notes

**Path Resolution**
- Accepts dot-notation keys: `elisa.provider.onboarding.welcome`
- Automatically strips locale prefix if present: `es.elisa.provider.onboarding.welcome` → `elisa.provider.onboarding.welcome`
- Handles nested YAML structures at any depth

**Indentation**
- Uses 2 spaces per indentation level (standard YAML)
- Array items are indented 2 spaces more than their parent key
- Preserves original indentation when applying corrections

**Quoting Logic**
Strings are quoted if they contain:
- Leading/trailing whitespace
- Special YAML characters: `: { } [ ] , & * # ? | - < > = ! % @ \``
- Quotes themselves
- Newlines
- Start with numbers (to avoid type confusion)

## Testing

Run the test suites:

```bash
# Test YamlValidator
bundle exec rspec spec/lib/elisa_verification/yaml_validator_spec.rb

# Test MessageCorrector
bundle exec rspec spec/lib/elisa_verification/message_corrector_spec.rb

# Run all elisa_verification tests
bundle exec rspec spec/lib/elisa_verification/
```

### YamlValidator Test Coverage

- ✅ Initialization with valid/invalid paths
- ✅ Syntax validation for valid YAML
- ✅ Syntax validation for invalid YAML (with line numbers)
- ✅ I18n validation via rails runner (mocked)
- ✅ Interpolation syntax validation (all incorrect patterns)
- ✅ Variable name validation (spaces, dashes, special chars)
- ✅ Unescaped character detection
- ✅ Combined validation (validate_all)
- ✅ Error reporting and formatting
- ✅ Exception handling

### MessageCorrector Test Coverage

- ✅ Initialization and file loading
- ✅ Simple string corrections
- ✅ Interpolation variable preservation
- ✅ Emoji and special character handling
- ✅ Spanish punctuation (¡, ¿, etc.)
- ✅ Array value corrections
- ✅ Comment preservation
- ✅ Indentation preservation
- ✅ UTF-8 encoding
- ✅ Quoting logic
- ✅ Non-existent key handling
- ✅ File saving

## Implementation Details

### YamlValidator Implementation

**validate_syntax**
- Uses YAML.load_file with safe mode
- Catches Psych::SyntaxError for parsing errors
- Extracts line numbers and error context
- Handles general StandardError for other issues

**validate_interpolation**
- Reads file line-by-line for detailed error reporting
- Skips comment lines
- Uses regex patterns to detect incorrect syntax
- Validates variable naming conventions
- Reports line numbers for each issue

**validate_i18n**
- Builds rails runner command with proper working directory
- Uses Open3.capture3 for output capture
- Checks exit status and stderr/stdout for errors
- Pattern matches common I18n error messages

### MessageCorrector Implementation

**find_key_line Method**

Searches for a specific key in the YAML file by traversing the nested structure:

1. Tracks indentation levels and matched keys
2. Handles backtracking when exiting nested scopes
3. Matches keys sequentially based on the dot-notation path
4. Returns the line index where the target key is found

**apply_string_correction Method**

Replaces a string value while preserving the key and indentation:

1. Extracts current indentation and key name
2. Determines if the new value needs quoting
3. Escapes quotes if necessary
4. Replaces the entire line with key: value format

**apply_array_correction Method**

Replaces an array value while preserving indentation:

1. Finds where the current array ends (looks for change in indentation)
2. Builds new array lines with proper indentation
3. Quotes array items if necessary
4. Replaces the old array lines with new ones

## Design Decisions

### Why Line-by-Line Instead of YAML AST?

YAML AST libraries (like Psych) typically lose:
- Comments
- Blank lines
- Custom formatting
- Exact whitespace

For a one-time verification task where preserving the exact file structure is critical, line-by-line string manipulation is more reliable.

### Why Preserve Everything?

The `elisa_es.yml` file contains:
- Flow ID comments (P1A, C5A, etc.) that map messages to specification sections
- Variable documentation explaining what interpolation variables are available
- Section headers organizing messages by category
- Blank lines improving readability

All of these are valuable for future maintainers and should not be lost during corrections.

### Why Multiple Validation Methods?

Separating validations allows:
- **Early exit on syntax errors** - No point checking interpolation if YAML can't parse
- **Targeted validation** - Run only what you need (syntax check before committing)
- **Better error messages** - Clear categories help developers fix issues faster
- **Flexible workflows** - Skip slow I18n validation during development

## Future Enhancements

- [ ] Full hash value correction support
- [ ] Multiline string handling (|, >)
- [ ] Backup file creation before saving
- [ ] Diff generation showing before/after
- [ ] Batch correction API
- [ ] Validation caching for large files
- [ ] Custom interpolation pattern support

## Related Components

- **V5SpecParser**: Extracts reference messages from KIRO_PROMPT_FLOWS_v5.md
- **YamlLoader**: Loads and parses YAML files with comment extraction
- **MessageComparator**: Compares YAML messages against v5 references
- **ValidationResult**: Value object for validation results (used by YamlValidator)
- **MessageComparison**: Value object for tracking comparisons

