# ElisaAudit Service Module

This module provides the foundation for the Elisa Message Copy Verification and Correction system - Phase 1 (Audit).

## Overview

The ElisaAudit module contains the base configuration and data models needed to audit all Elisa conversational messages against the official UX copy specification documented in `trato-flujos-v4-ux-copy.pdf`.

## Directory Structure

```
app/services/elisa_audit/
├── README.md                          # This file
├── ai_usage_rules.rb                 # AI usage rules configuration module
├── data_models.rb                    # Core data structures (Structs)
├── errors.rb                         # Custom error classes
├── yaml_inventory_generator.rb       # YAML inventory generator service
├── ai_usage_analyzer.rb              # AI usage analyzer service
├── whats_app_template_detector.rb    # WhatsApp template detector service
└── audit_report_generator.rb         # Audit report generator service

spec/services/elisa_audit/
├── ai_usage_rules_spec.rb            # Tests for AI usage rules
├── data_models_spec.rb               # Tests for data models
├── yaml_inventory_generator_spec.rb  # Tests for YAML inventory generator
├── ai_usage_analyzer_spec.rb         # Tests for AI usage analyzer
├── whats_app_template_detector_spec.rb # Tests for template detector
└── audit_report_generator_spec.rb    # Tests for audit report generator
```

## Components

### 1. AiUsageRules Module (`ai_usage_rules.rb`)

Configuration module defining AI usage expectations for all 50 Elisa flows (P1A-P20 provider flows, C1A-C7D client flows).

**Purpose:**
- Serves as the source of truth for which flows should use AI and how
- Documents which flows must be fixed templates (never AI-generated)
- Identifies proactive messages requiring WhatsApp Message Templates

**Key Constants:**
- `FLOWS`: Hash mapping flow IDs to their AI configuration
- `PROACTIVE_TEMPLATES`: Array of flows requiring WhatsApp templates

**Flow Types:**
- `:fixed_template` - No AI, message is 100% static
- `:extraction` - AI converts free text to structured data
- `:generation` - AI generates message content shown to user
- `:interpretation` - AI determines conversational branch/routing
- `:tagging` - AI categorizes photos
- `:detection_semantic` - AI detects semantic meaning

**Status Categories:**
- `:correct` - Implementation is correct, do not modify
- `:verify` - Requires verification during audit
- `:implement` - Needs to be implemented
- `:critical_verify` - Critical verification needed
- `:undocumented` - Not documented in AI usage rules

**Public Methods:**
```ruby
ElisaAudit::AiUsageRules.expected_for_flow('P6A')
# => { type: :generation, model: :sonnet, status: :correct, ... }

ElisaAudit::AiUsageRules.proactive?('P16')
# => true

ElisaAudit::AiUsageRules.flows_by_type(:extraction)
# => ['P3E', 'C2D', 'C3A']

ElisaAudit::AiUsageRules.flows_by_model(:haiku)
# => ['P3E', 'P15', 'P16', ...]

ElisaAudit::AiUsageRules.flows_by_status(:critical_verify)
# => ['P10-P14']
```

### 2. Data Models (`data_models.rb`)

Core Struct definitions for audit data:

#### MessageEntry
Represents a single message entry from `elisa_es.yml`

**Fields:**
- `flow_id`: Flow identifier (e.g., 'P1A', 'C7A')
- `yaml_key`: Full YAML key path
- `content`: Actual message text
- `line_number`: Line number in elisa_es.yml
- `variables`: Array of interpolation variables

**Methods:**
- `has_variables?`: Returns true if message has interpolation variables
- `formatted_variables`: Returns comma-separated list of variables with %{} syntax

#### AiUsageViolation
Represents an AI usage violation found during audit

**Fields:**
- `type`: Violation type (:improper_generation, :missing_extraction, :missing_interpretation)
- `flow_id`: Flow identifier
- `file_path`: Path to service file
- `line_number`: Line number in file
- `method_name`: Method where violation occurs
- `current_impl`: Description of current implementation
- `expected_impl`: Description of correct implementation
- `severity`: :critical, :moderate, or :minor
- `model_used`: :haiku, :sonnet, or nil

**Methods:**
- `severity_label`: Returns human-readable severity badge
- `type_label`: Returns Spanish violation type label

#### TemplateRequirement
Represents a WhatsApp Message Template requirement

**Fields:**
- `flow_id`: Flow identifier
- `template_name`: Suggested template name for Meta registration
- `category`: 'UTILITY' or 'MARKETING'
- `message_text`: Exact template text with {{variable}} syntax
- `variables`: Array of variable definitions
- `is_proactive`: Boolean, sent outside 24h window?
- `yaml_key`: Corresponding YAML key

**Methods:**
- `formatted_variables`: Returns formatted variable list for Meta template registration
- `category_badge`: Returns WhatsApp category badge

#### ComparisonEntry
Represents a manual comparison entry (template for developer to fill during audit)

**Fields:**
- `flow_id`: Flow identifier
- `yaml_key`: Full YAML key path
- `current_text`: Text in elisa_es.yml
- `pdf_text`: Text from PDF (filled manually during audit)
- `status`: :exact_match, :mismatch, :missing, or :extra (filled manually)
- `notes`: Additional context (filled manually)

**Methods:**
- `status_badge`: Returns status badge for display
- `requires_attention?`: Returns true if entry requires attention

## Usage Examples

### Check AI usage for a flow
```ruby
config = ElisaAudit::AiUsageRules.expected_for_flow('P6A')
puts config[:type]        # => :generation
puts config[:model]       # => :sonnet
puts config[:generates]   # => "[BIO]"
```

### Check if flow is proactive
```ruby
if ElisaAudit::AiUsageRules.proactive?('P16')
  puts "This flow requires WhatsApp Message Template"
end
```

### Create a message entry
```ruby
entry = ElisaAudit::MessageEntry.new(
  flow_id: 'P1A',
  yaml_key: 'elisa.provider.onboarding.welcome',
  content: '¡Hola! 👋 Soy Elisa...',
  line_number: 42,
  variables: ['name']
)

puts entry.has_variables?       # => true
puts entry.formatted_variables  # => "%{name}"
```

### Create an AI violation
```ruby
violation = ElisaAudit::AiUsageViolation.new(
  type: :improper_generation,
  flow_id: 'P10-P14',
  file_path: 'app/services/provider_conversation_handler.rb',
  line_number: 156,
  method_name: 'send_thank_you_message',
  current_impl: 'Using ClaudeService.call to generate message',
  expected_impl: 'Must be fixed template from elisa_es.yml',
  severity: :critical,
  model_used: :haiku
)

puts violation.severity_label  # => "🔴 CRÍTICO"
puts violation.type_label      # => "Generación impropia"
```

### 3. AuditReportGenerator Service (`audit_report_generator.rb`)

Service to aggregate all audit findings and generate comprehensive markdown report.

**Purpose:**
- Orchestrate Phase 1 audit report generation
- Aggregate outputs from YamlInventoryGenerator, AiUsageAnalyzer, and WhatsAppTemplateDetector
- Generate markdown report with six main sections:
  1. Executive Summary - Statistics and risk assessment
  2. Manual Comparison Template - For developer to fill during PDF comparison
  3. AI Usage Violations - All detected AI issues grouped by severity
  4. WhatsApp Message Templates - Required templates for Meta approval
  5. Implementation Analysis - Current state vs. specification
  6. Phase 2 Recommendations - Prioritized task list

**Input Requirements:**
- `yaml_inventory`: Hash from YamlInventoryGenerator with :markdown, :entries, :stats
- `ai_violations`: Array of AiUsageViolation structs from AiUsageAnalyzer
- `template_requirements`: Array of TemplateRequirement structs from WhatsAppTemplateDetector

**Output:**
- Hash with:
  - `:markdown` - Complete markdown report content
  - `:output_path` - Path to saved report file
  - `:stats` - Summary statistics

**Interface:**
```ruby
generator = ElisaAudit::AuditReportGenerator.new

result = generator.call(
  yaml_inventory: yaml_inventory_result,
  ai_violations: violations_array,
  template_requirements: templates_array
)

puts result[:markdown]       # Full report content
puts result[:output_path]    # ".kiro/specs/.../phase1-audit-report.md"
puts result[:stats][:total_violations]  # 10
```

**Report Structure:**
- **Executive Summary:** High-level statistics, risk assessment, Phase 2 readiness
- **Comparison Template:** Structured table for manual PDF-to-YAML comparison
- **AI Violations:** Grouped by severity (🔴 Critical, 🟡 Moderate, 🟢 Minor)
- **Templates:** All WhatsApp Message Templates with variables for Meta registration
- **Implementation Analysis:** Flow-by-flow status (correct, verify, implement)
- **Phase 2 Recommendations:** Prioritized task sequence with effort estimates

**Key Features:**
- Automatic risk assessment based on violation counts
- Readiness checklist for Phase 2 (prerequisites validation)
- Prioritized task generation (critical fixes first)
- Comprehensive Meta template registration guidance
- Estimated effort and complexity for each correction task

## Testing

All components have comprehensive test coverage:

```bash
# Run all elisa_audit specs
bundle exec rspec spec/services/elisa_audit/

# Run specific specs
bundle exec rspec spec/services/elisa_audit/ai_usage_rules_spec.rb
bundle exec rspec spec/services/elisa_audit/data_models_spec.rb
```

**Test Coverage:**
- AiUsageRules: 37 examples, 0 failures
- DataModels: 29 examples, 0 failures
- YamlInventoryGenerator: 42 examples, 0 failures
- AiUsageAnalyzer: 41 examples, 0 failures
- WhatsAppTemplateDetector: 36 examples, 0 failures
- AuditReportGenerator: 34 examples, 0 failures
- **Total: 219 examples, 0 failures**

## Design Principles

Following Trato project rules:

1. **Comprehensive Comments**: All methods and classes are fully documented
2. **Frozen String Literals**: Enabled on all files
3. **Guard Clauses**: Used throughout for early returns
4. **Module Organization**: Business logic properly organized in service modules
5. **Testing**: Using RSpec with context blocks for different scenarios

## Next Steps

All Phase 1 audit services have been implemented! ✅

**Implemented Services:**

1. ✅ `YamlInventoryGenerator` - Generates structured YAML inventory
2. ✅ `AiUsageAnalyzer` - Analyzes ClaudeService.call usage
3. ✅ `WhatsAppTemplateDetector` - Identifies proactive messages
4. ✅ `AuditReportGenerator` - Aggregates and formats report

**Ready for Phase 1 Audit Execution:**

To generate the Phase 1 audit report:

```ruby
# Generate YAML inventory
yaml_generator = ElisaAudit::YamlInventoryGenerator.new
yaml_result = yaml_generator.call

# Analyze AI usage
ai_analyzer = ElisaAudit::AiUsageAnalyzer.new
violations = ai_analyzer.call

# Detect template requirements
template_detector = ElisaAudit::WhatsAppTemplateDetector.new
templates = template_detector.call

# Generate comprehensive audit report
report_generator = ElisaAudit::AuditReportGenerator.new
report = report_generator.call(
  yaml_inventory: yaml_result,
  ai_violations: violations,
  template_requirements: templates
)

# Report saved to: .kiro/specs/elisa-message-copy-verification/phase1-audit-report.md
puts "Audit report generated: #{report[:output_path]}"
```

Or use the provided Rake task:

```bash
rake elisa_audit:generate_report
```

## Related Documents

- Requirements: `.kiro/specs/elisa-message-copy-verification/requirements.md`
- Design: `.kiro/specs/elisa-message-copy-verification/design.md`
- Tasks: `.kiro/specs/elisa-message-copy-verification/tasks.md`
- AI Usage Rules: `prompt-kiro-correccion-copys-ia.md`
