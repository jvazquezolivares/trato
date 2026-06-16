# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ElisaAudit::AuditReportGenerator do
  subject(:generator) { described_class.new }

  let(:yaml_inventory) do
    {
      markdown: "# Sample inventory...",
      entries: [
        ElisaAudit::MessageEntry.new(
          flow_id: 'P1A',
          yaml_key: 'es.elisa.provider.onboarding.welcome',
          content: '¡Hola! Soy Elisa...',
          line_number: 42,
          variables: []
        ),
        ElisaAudit::MessageEntry.new(
          flow_id: 'C7A',
          yaml_key: 'es.elisa.client.review.request',
          content: '¿Cómo te fue con %{provider_name}?',
          line_number: 156,
          variables: ['provider_name']
        )
      ],
      stats: {
        total: 2,
        provider: 1,
        client: 1,
        unknown: 0
      }
    }
  end

  let(:ai_violations) do
    [
      ElisaAudit::AiUsageViolation.new(
        type: :improper_generation,
        flow_id: 'P10-P14',
        file_path: 'app/services/provider_conversation_handler.rb',
        line_number: 156,
        method_name: 'send_thank_you_message',
        current_impl: 'Using ClaudeService.call to generate message',
        expected_impl: 'Must be fixed template from elisa_es.yml',
        severity: :critical,
        model_used: :haiku
      ),
      ElisaAudit::AiUsageViolation.new(
        type: :wrong_model,
        flow_id: 'P6A',
        file_path: 'app/services/onboarding_service.rb',
        line_number: 89,
        method_name: 'generate_bio',
        current_impl: 'Using haiku model',
        expected_impl: 'Should use sonnet model',
        severity: :minor,
        model_used: :haiku
      )
    ]
  end

  let(:template_requirements) do
    [
      ElisaAudit::TemplateRequirement.new(
        flow_id: 'P10-P14',
        template_name: 'provider_thank_you_review_request',
        category: 'UTILITY',
        message_text: 'Gracias {{nombre_proveedor}}...',
        variables: [{ name: 'nombre_proveedor', type: 'text', example: 'Miguel' }],
        is_proactive: true,
        yaml_key: 'es.elisa.provider.completion.thank_you (MISSING)'
      )
    ]
  end

  describe '#call' do
    context 'when all inputs are valid' do
      it 'generates complete audit report' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        expect(result).to be_a(Hash)
        expect(result).to have_key(:markdown)
        expect(result).to have_key(:output_path)
        expect(result).to have_key(:stats)
      end

      it 'returns markdown string' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        expect(result[:markdown]).to be_a(String)
        expect(result[:markdown]).not_to be_empty
      end

      it 'includes all main sections in markdown' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        # Check for main sections
        expect(markdown).to include('# Phase 1 Audit Report')
        expect(markdown).to include('## 1. Executive Summary')
        expect(markdown).to include('## 2. YAML Syntax Validation')
        expect(markdown).to include('## 3. Manual Comparison Template')
        expect(markdown).to include('## 4. AI Usage Violations')
        expect(markdown).to include('## 5. WhatsApp Message Templates')
        expect(markdown).to include('## 5. Placeholder Consistency Analysis')
        expect(markdown).to include('## 6. Implementation Analysis')
        expect(markdown).to include('## 7. Flow-to-YAML Mapping')
        expect(markdown).to include('## 8. Phase 2 Task Recommendations')
        expect(markdown).to include('## 9. Pendientes / Fuera de Alcance')
      end

      it 'includes statistics in executive summary' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        expect(markdown).to include('**Total messages found:** 2')
        expect(markdown).to include('**Provider messages (P1-P20):** 1')
        expect(markdown).to include('**Client messages (C1-C7):** 1')
        expect(markdown).to include('**Total violations detected:** 2')
        expect(markdown).to include('**🔴 Critical violations:** 1')
        expect(markdown).to include('**🟢 Minor violations:** 1')
      end

      it 'returns correct output path' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        expect(result[:output_path]).to include('phase1-audit-report.md')
      end

      it 'returns complete stats hash' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        stats = result[:stats]

        expect(stats).to include(
          total_messages: 2,
          provider_messages: 1,
          client_messages: 1,
          total_violations: 2,
          critical_violations: 1,
          moderate_violations: 0,
          minor_violations: 1,
          template_requirements: 1,
          missing_templates: 1
        )
      end
    end

    context 'when there are critical violations' do
      it 'includes high risk assessment' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        expect(markdown).to include('**🔴 HIGH RISK:**')
        expect(markdown).to include('critical violation(s) detected')
      end

      it 'lists critical violations in dedicated section' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        expect(markdown).to include('### 🔴 Critical Violations')
        expect(markdown).to include('P10-P14')
        expect(markdown).to include('send_thank_you_message')
      end

      it 'includes critical fixes in Phase 2 recommendations' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        expect(markdown).to include('Category 1: Critical AI Implementation Changes')
        expect(markdown).to include('Priority: 🔴 CRITICAL')
      end
    end

    context 'when there are no violations' do
      let(:no_violations) { [] }

      it 'shows no violations message' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: no_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        expect(markdown).to include('**✅ No violations detected!**')
        expect(markdown).to include('No corrections needed for AI implementation')
      end

      it 'shows low/no risk assessment' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: no_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        expect(markdown).to include('**✅ NO RISK:**')
      end
    end

    context 'when there are missing templates' do
      it 'includes missing template warnings' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        expect(markdown).to include('**Missing template messages:** 1')
      end

      it 'marks missing templates with warning badge' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        expect(markdown).to include('⚠️ _MISSING_')
      end

      it 'includes task to create missing templates' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        expect(markdown).to include('Category 2: Message Corrections')
        expect(markdown).to include('Priority: 🟡 HIGH')
      end
    end

    context 'when there are moderate violations' do
      let(:moderate_violations) do
        [
          ElisaAudit::AiUsageViolation.new(
            type: :improper_generation,
            flow_id: 'P15',
            file_path: 'app/services/provider_conversation_handler.rb',
            line_number: 200,
            method_name: 'detect_expense',
            current_impl: 'Using AI for generation',
            expected_impl: 'Should only use AI for interpretation',
            severity: :moderate,
            model_used: :haiku
          )
        ]
      end

      it 'includes moderate violations section' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: moderate_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        expect(markdown).to include('### 🟡 Moderate Violations')
        expect(markdown).to include('P15')
      end

      it 'shows moderate risk when more than 5 moderate violations' do
        many_moderate = Array.new(6) do |i|
          ElisaAudit::AiUsageViolation.new(
            type: :improper_generation,
            flow_id: "P#{i}",
            file_path: 'app/services/test.rb',
            line_number: i,
            method_name: 'test',
            current_impl: 'test',
            expected_impl: 'test',
            severity: :moderate,
            model_used: :haiku
          )
        end

        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: many_moderate,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        expect(markdown).to include('**🟡 MODERATE RISK:**')
      end
    end

    context 'when creating comparison template' do
      it 'includes instructions for manual comparison' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        expect(markdown).to include('**Instructions:**')
        expect(markdown).to include('Open `trato-flujos-v4-ux-copy.pdf`')
        expect(markdown).to include('Fill in the "PDF Text (Source of Truth)" column')
      end

      it 'creates separate tables for provider and client messages' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        expect(markdown).to include('### Provider Messages Comparison (P1A-P20)')
        expect(markdown).to include('### Client Messages Comparison (C1A-C7D)')
      end

      it 'includes placeholder columns for manual filling' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        expect(markdown).to include('_[TO FILL]_')
      end

      it 'includes note about C2A being out of scope' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        expect(markdown).to include('C2A is out of scope')
        expect(markdown).to include('Pendiente de definición')
      end
    end

    context 'when listing WhatsApp templates' do
      it 'groups templates by flow ID' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        expect(markdown).to include('#### Flow P10-P14')
        expect(markdown).to include('provider_thank_you_review_request')
      end

      it 'includes template message text' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        expect(markdown).to include('Gracias {{nombre_proveedor}}...')
      end

      it 'includes template variables' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        expect(markdown).to include('nombre_proveedor')
        expect(markdown).to include('Miguel')
      end

      it 'includes Meta submission guidance' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        expect(markdown).to include('### Meta Submission Guidance')
        expect(markdown).to include('UTILITY')
        expect(markdown).to include('Spanish (es)')
      end
    end

    context 'when generating implementation analysis' do
      it 'groups flows by status' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        expect(markdown).to include('#### ✅ Correct Flows')
        expect(markdown).to include('#### ⏳ Verify Flows')
        expect(markdown).to include('#### 🔴 Critical Verify Flows')
        expect(markdown).to include('#### 🚧 Implement Flows')
      end

      it 'marks correct flows as do not modify' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        expect(markdown).to include('Do Not Touch')
        expect(markdown).to include('**Do not modify.**')
      end

      it 'includes file and line references for flows with violations' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        # P10-P14 has a violation, should show file/line reference
        expect(markdown).to include('**Implementation references:**')
        expect(markdown).to include('provider_conversation_handler.rb:156')
        expect(markdown).to include('send_thank_you_message')
      end

      it 'notes when AI flows have no violations' do
        # Remove violations so AI flows show "no violations detected" message
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: [],
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        # Flows with AI usage (model specified) but no violations should show note
        expect(markdown).to include('_Implementation uses AI as specified, no violations detected_')
      end

      it 'includes model assignments summary' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        expect(markdown).to include('### Model Assignments (MUST PRESERVE)')
        expect(markdown).to include('**Haiku Flows')
        expect(markdown).to include('**Sonnet Flows')
        expect(markdown).to include('**Rationale:**')
      end

      it 'lists all Haiku flows in model assignments' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        # Check for some known Haiku flows from AiUsageRules
        expect(markdown).to include('P3E') # Extraction flow using Haiku
        expect(markdown).to include('C2D') # Extraction flow using Haiku
      end

      it 'lists all Sonnet flows in model assignments' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        # Check for known Sonnet flows from AiUsageRules
        expect(markdown).to include('P6A') # Bio generation using Sonnet
        expect(markdown).to include('P6B') # Bio regeneration using Sonnet
      end

      it 'includes preservation warning in model assignments' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        expect(markdown).to include('IMPORTANT')
        expect(markdown).to include('must be preserved during all corrections')
        expect(markdown).to include('Do not change Haiku to Sonnet')
      end
    end

    context 'when generating Phase 2 recommendations' do
      it 'includes prioritization strategy with categories' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        expect(markdown).to include('### Prioritization Strategy')
        expect(markdown).to include('🔴 Critical violations')
        expect(markdown).to include('🟡 Message corrections')
        expect(markdown).to include('🟡 AI implementation changes')
        expect(markdown).to include('🟢 Template preparation')
      end

      it 'includes task categories section' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        expect(markdown).to include('### Task Categories')
      end

      it 'generates Category 1: Critical AI Implementation Changes' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        expect(markdown).to include('#### Category 1: Critical AI Implementation Changes')
        expect(markdown).to include('Priority: 🔴 CRITICAL')
        expect(markdown).to include('**Complexity:** Complex')
        expect(markdown).to include('**Affected Flows:** P10-P14')
      end

      it 'includes file paths and line numbers in critical tasks' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        # Check for detailed task with file/line reference
        expect(markdown).to include('provider_conversation_handler.rb:156')
        expect(markdown).to include('**Method:** `send_thank_you_message`')
        expect(markdown).to include('**Current:** Using ClaudeService.call to generate message')
        expect(markdown).to include('**Expected:** Must be fixed template from elisa_es.yml')
      end

      it 'generates Category 2: Message Corrections' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        expect(markdown).to include('#### Category 2: Message Corrections')
        expect(markdown).to include('Priority: 🟡 HIGH')
        expect(markdown).to include('**Complexity:** Simple (text updates in YAML file)')
        expect(markdown).to include('**Files to Modify:** `config/locales/elisa_es.yml`')
      end

      it 'includes missing template creation in message corrections' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        expect(markdown).to include('**2.1 Create Missing Message Templates**')
        expect(markdown).to include('es.elisa.provider.completion.thank_you')
        expect(markdown).to include('flow **P10-P14**')
      end

      it 'includes manual comparison task in message corrections' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        expect(markdown).to include('**2.2 Complete Manual PDF Comparison**')
        expect(markdown).to include('Fill Section 2 comparison template')
        expect(markdown).to include('trato-flujos-v4-ux-copy.pdf')
      end

      it 'includes apply corrections task in message corrections' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        expect(markdown).to include('**2.3 Apply Message Corrections**')
        expect(markdown).to include('Preserve interpolation variables')
        expect(markdown).to include('bundle exec rake i18n:check')
      end

      it 'generates Category 4: Minor AI Implementation Changes when present' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        expect(markdown).to include('#### Category 4: Minor AI Implementation Changes')
        expect(markdown).to include('Priority: 🟢 LOW')
        expect(markdown).to include('**Complexity:** Simple (parameter updates only)')
        expect(markdown).to include('P6A')
      end

      it 'includes detailed model assignment fix in minor tasks' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        # Check for P6A model fix details
        expect(markdown).to include('onboarding_service.rb:89')
        expect(markdown).to include('**Flow:** P6A')
        expect(markdown).to include('**Current model:** `:haiku`')
        expect(markdown).to include('**Expected model:** `:sonnet`')
        expect(markdown).to include('Change `model: :haiku` to `model: :sonnet`')
      end

      it 'generates Category 5: Template Preparation' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        expect(markdown).to include('#### Category 5: Template Preparation')
        expect(markdown).to include('Priority: 🟢 LOW')
        expect(markdown).to include('**Complexity:** Moderate (external approval process with Meta)')
      end

      it 'includes all template preparation subtasks' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        expect(markdown).to include('Format templates for Meta submission')
        expect(markdown).to include('Submit templates via WhatsApp Business API Manager')
        expect(markdown).to include('Store approved template IDs in Rails configuration')
        expect(markdown).to include('Update services to use template IDs')
      end

      it 'includes summary with task counts by category' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        expect(markdown).to include('### Summary')
        expect(markdown).to include('**Total Tasks by Category:**')
        expect(markdown).to include('🔴 Critical AI changes: 1')
        expect(markdown).to include('🟡 Message corrections:')
        expect(markdown).to include('🟢 Minor AI changes: 1')
        expect(markdown).to include('🟢 Template preparation: 4')
      end

      it 'includes estimated total effort with breakdown' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        expect(markdown).to include('**Estimated Total Effort:**')
        expect(markdown).to include('Critical AI fixes:')
        expect(markdown).to include('Message corrections:')
        expect(markdown).to include('Minor AI fixes:')
        expect(markdown).to include('Template preparation:')
        expect(markdown).to include('**Total development time:**')
        expect(markdown).to include('**Total calendar time:**')
      end

      it 'includes prerequisites checklist before starting Phase 2' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        expect(markdown).to include('### Prerequisites Before Starting Phase 2')
        expect(markdown).to include('Review this audit report with technical team')
        expect(markdown).to include('Review this audit report with UX/product team')
        expect(markdown).to include('Get approval for critical violation fixes')
        expect(markdown).to include('Prepare test strategy')
        expect(markdown).to include('Plan deployment strategy')
      end

      it 'includes recommended implementation order with timeline' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        expect(markdown).to include('### Recommended Implementation Order')
        expect(markdown).to include('**Day 1 Morning:** Fix critical AI violations')
        expect(markdown).to include('**Day 1 Afternoon:** Complete manual PDF comparison')
        expect(markdown).to include('**Day 2 Morning:** Create missing templates + apply corrections')
        expect(markdown).to include('**Day 2 Afternoon:** Submit templates to Meta')
        expect(markdown).to include('**Day 5:** Deploy to production with monitoring')
      end

      context 'when there are moderate violations' do
        let(:moderate_violations) do
          [
            ElisaAudit::AiUsageViolation.new(
              type: :missing_extraction,
              flow_id: 'P15',
              file_path: 'app/services/provider_conversation_handler.rb',
              line_number: 200,
              method_name: 'detect_expense',
              current_impl: 'Not using AI extraction',
              expected_impl: 'Should use AI to extract expense data',
              severity: :moderate,
              model_used: nil
            )
          ]
        end

        it 'generates Category 3: Moderate AI Implementation Changes' do
          result = generator.call(
            yaml_inventory: yaml_inventory,
            ai_violations: moderate_violations,
            template_requirements: template_requirements
          )

          markdown = result[:markdown]

          expect(markdown).to include('#### Category 3: Moderate AI Implementation Changes')
          expect(markdown).to include('Priority: 🟢 MEDIUM')
          expect(markdown).to include('**Complexity:** Moderate (requires service logic changes)')
          expect(markdown).to include('**Affected Flows:** P15')
        end

        it 'includes file paths and details in moderate tasks' do
          result = generator.call(
            yaml_inventory: yaml_inventory,
            ai_violations: moderate_violations,
            template_requirements: template_requirements
          )

          markdown = result[:markdown]

          expect(markdown).to include('provider_conversation_handler.rb:200')
          expect(markdown).to include('**Method:** `detect_expense`')
          expect(markdown).to include('**Issue:** Not using AI extraction')
          expect(markdown).to include('**Fix:** Should use AI to extract expense data')
        end
      end

      context 'when there are no violations' do
        it 'skips violation categories' do
          result = generator.call(
            yaml_inventory: yaml_inventory,
            ai_violations: [],
            template_requirements: template_requirements
          )

          markdown = result[:markdown]

          # Should not include critical/moderate/minor categories if no violations
          expect(markdown).not_to include('#### Category 1: Critical AI Implementation Changes')
          expect(markdown).not_to include('#### Category 3: Moderate AI Implementation Changes')
          expect(markdown).not_to include('#### Category 4: Minor AI Implementation Changes')

          # Should still include message corrections and template preparation
          expect(markdown).to include('#### Category 2: Message Corrections')
          expect(markdown).to include('#### Category 5: Template Preparation')
        end
      end

      context 'when there are no missing templates' do
        let(:no_missing_templates) do
          [
            ElisaAudit::TemplateRequirement.new(
              flow_id: 'P10-P14',
              template_name: 'provider_thank_you',
              category: 'UTILITY',
              message_text: 'Gracias...',
              variables: [],
              is_proactive: true,
              yaml_key: 'es.elisa.provider.completion.thank_you'
            )
          ]
        end

        it 'skips missing template creation task' do
          result = generator.call(
            yaml_inventory: yaml_inventory,
            ai_violations: ai_violations,
            template_requirements: no_missing_templates
          )

          markdown = result[:markdown]

          expect(markdown).not_to include('**2.1 Create Missing Message Templates**')
          expect(markdown).not_to include('(MISSING')
        end
      end

      context 'when tasks are grouped by flow ID' do
        let(:multiple_critical_violations) do
          [
            ElisaAudit::AiUsageViolation.new(
              type: :improper_generation,
              flow_id: 'P10-P14',
              file_path: 'app/services/provider_conversation_handler.rb',
              line_number: 156,
              method_name: 'send_thank_you_message',
              current_impl: 'Using AI to generate',
              expected_impl: 'Must be fixed template',
              severity: :critical,
              model_used: :haiku
            ),
            ElisaAudit::AiUsageViolation.new(
              type: :improper_generation,
              flow_id: 'P10-P14',
              file_path: 'app/services/provider_conversation_handler.rb',
              line_number: 180,
              method_name: 'send_review_request',
              current_impl: 'Using AI to generate review request',
              expected_impl: 'Must be fixed template',
              severity: :critical,
              model_used: :haiku
            )
          ]
        end

        it 'groups multiple violations from same flow' do
          result = generator.call(
            yaml_inventory: yaml_inventory,
            ai_violations: multiple_critical_violations,
            template_requirements: template_requirements
          )

          markdown = result[:markdown]

          # Should have single "Flow P10-P14" header with both violations under it
          flow_headers = markdown.scan(/\*\*Flow P10-P14:\*\*/)
          expect(flow_headers.count).to eq(1)

          # Should include both methods
          expect(markdown).to include('send_thank_you_message')
          expect(markdown).to include('send_review_request')
        end
      end

      context 'when complexity estimates are provided' do
        it 'labels critical tasks as complex' do
          result = generator.call(
            yaml_inventory: yaml_inventory,
            ai_violations: ai_violations,
            template_requirements: template_requirements
          )

          markdown = result[:markdown]

          # Critical tasks should be marked as Complex
          critical_section = markdown[/Category 1.*?Category 2/m]
          expect(critical_section).to include('**Complexity:** Complex')
        end

        it 'labels message corrections as simple' do
          result = generator.call(
            yaml_inventory: yaml_inventory,
            ai_violations: ai_violations,
            template_requirements: template_requirements
          )

          markdown = result[:markdown]

          # Message corrections should be marked as Simple
          message_section = markdown[/Category 2.*?Category/m]
          expect(message_section).to include('**Complexity:** Simple')
        end

        it 'labels minor tasks as simple' do
          result = generator.call(
            yaml_inventory: yaml_inventory,
            ai_violations: ai_violations,
            template_requirements: template_requirements
          )

          markdown = result[:markdown]

          # Minor tasks should be marked as Simple
          minor_section = markdown[/Category 4.*?(Category|###)/m]
          expect(minor_section).to include('**Complexity:** Simple')
        end

        it 'labels template preparation as moderate' do
          result = generator.call(
            yaml_inventory: yaml_inventory,
            ai_violations: ai_violations,
            template_requirements: template_requirements
          )

          markdown = result[:markdown]

          # Template preparation should be marked as Moderate
          template_section = markdown[/Category 5.*?###/m]
          expect(template_section).to include('**Complexity:** Moderate')
        end
      end
    end

    context 'when file write fails' do
      before do
        allow(File).to receive(:write).and_raise(IOError.new('Permission denied'))
      end

      it 'raises ReportGenerationError' do
        expect do
          generator.call(
            yaml_inventory: yaml_inventory,
            ai_violations: ai_violations,
            template_requirements: template_requirements
          )
        end.to raise_error(ElisaAudit::ReportGenerationError, /Failed to write report/)
      end
    end

    context 'when output directory does not exist' do
      it 'creates the directory' do
        expect(FileUtils).to receive(:mkdir_p).with(
          File.dirname(described_class::OUTPUT_PATH)
        )

        generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )
      end
    end

    context 'when truncating long messages' do
      let(:long_message_entry) do
        ElisaAudit::MessageEntry.new(
          flow_id: 'P1A',
          yaml_key: 'es.elisa.provider.onboarding.welcome',
          content: 'A' * 100,
          line_number: 42,
          variables: []
        )
      end

      let(:long_message_inventory) do
        {
          markdown: "# Sample",
          entries: [long_message_entry],
          stats: { total: 1, provider: 1, client: 0, unknown: 0 }
        }
      end

      it 'truncates messages longer than max length' do
        result = generator.call(
          yaml_inventory: long_message_inventory,
          ai_violations: [],
          template_requirements: []
        )

        markdown = result[:markdown]

        # Message should be truncated with ellipsis
        expect(markdown).to include('A' * 40 + '...')
        expect(markdown).not_to include('A' * 100)
      end
    end

    context 'when escaping special markdown characters' do
      let(:pipe_message_entry) do
        ElisaAudit::MessageEntry.new(
          flow_id: 'P1A',
          yaml_key: 'es.elisa.provider.test',
          content: 'Test | with | pipes',
          line_number: 42,
          variables: []
        )
      end

      let(:pipe_inventory) do
        {
          markdown: "# Sample",
          entries: [pipe_message_entry],
          stats: { total: 1, provider: 1, client: 0, unknown: 0 }
        }
      end

      it 'escapes pipe characters in messages' do
        result = generator.call(
          yaml_inventory: pipe_inventory,
          ai_violations: [],
          template_requirements: []
        )

        markdown = result[:markdown]

        # Pipes should be escaped
        expect(markdown).to include('Test \\| with \\| pipes')
      end
    end

    context 'when generating AI_Usage_Rules references' do
      it 'includes AI Rules Reference column in violations table' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        # Check for the new column header
        expect(markdown).to include('| Flow ID | Type | File | Line | Method | Current Implementation | Expected Implementation | AI Rules Reference |')
      end

      it 'includes AI_Usage_Rules reference for each violation' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        # P10-P14 should show fixed_template type
        expect(markdown).to include('Type: `fixed_template`')
        expect(markdown).to include('Status: `critical_verify`')

        # P6A should show generation type and sonnet model (expected)
        expect(markdown).to include('Type: `generation`')
        expect(markdown).to include('Model: `sonnet`')
      end

      it 'includes AI_Usage_Rules reference legend' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        expect(markdown).to include('**AI_Usage_Rules Reference Legend:**')
        expect(markdown).to include('**Type**: Flow classification')
        expect(markdown).to include('**Model**: Required Claude model')
        expect(markdown).to include('**Status**: Implementation status')
        expect(markdown).to include('See `app/services/elisa_audit/ai_usage_rules.rb`')
        expect(markdown).to include('See `prompt-kiro-correccion-copys-ia.md`')
      end

      it 'handles undocumented flows gracefully' do
        undocumented_violation = ElisaAudit::AiUsageViolation.new(
          type: :improper_generation,
          flow_id: 'UNKNOWN',
          file_path: 'app/services/test.rb',
          line_number: 1,
          method_name: 'test_method',
          current_impl: 'Test',
          expected_impl: 'Test',
          severity: :moderate,
          model_used: :haiku
        )

        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: [undocumented_violation],
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        expect(markdown).to include('⚠️ Not documented')
      end

      it 'shows model only when specified in AI_Usage_Rules' do
        # P10-P14 is fixed_template with no model - should not show Model field
        p10_violation = ai_violations.find { |v| v.flow_id == 'P10-P14' }

        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: [p10_violation],
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        # Extract the P10-P14 row
        p10_row = markdown.lines.find { |line| line.include?('P10-P14') && line.include?('Type: `fixed_template`') }
        expect(p10_row).to be_present

        # Should not include Model field for fixed_template flows
        # (they have model: nil in AiUsageRules)
        # Split the row and check the AI Rules Reference column doesn't have "Model:"
        ai_rules_column = p10_row.split('|')[-2] # Second to last column
        expect(ai_rules_column).not_to include('Model:')
      end
    end

    context 'when generating Flow-to-YAML Mapping section' do
      it 'includes Flow-to-YAML Mapping section' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        expect(markdown).to include('## 7. Flow-to-YAML Mapping')
      end

      it 'includes status legend explaining all status types' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        expect(markdown).to include('**Status Legend:**')
        expect(markdown).to include('✅ **Matches**')
        expect(markdown).to include('❌ **Discrepancy**')
        expect(markdown).to include('⚠️ **Missing**')
        expect(markdown).to include('⚠️ **Extra**')
        expect(markdown).to include('🔴 **AI Violation**')
      end

      it 'includes separate tables for provider and client flows' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        expect(markdown).to include('### Provider Flows (P1A-P20)')
        expect(markdown).to include('### Client Flows (C1A-C7D)')
      end

      it 'includes navigation help section' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        expect(markdown).to include('### Using This Mapping')
        expect(markdown).to include('**For PDF → YAML navigation:**')
        expect(markdown).to include('**For YAML → PDF navigation:**')
        expect(markdown).to include('**For AI violation investigation:**')
      end

      it 'creates table with all required columns' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        expect(markdown).to include('| Flow ID | YAML Key | Line | Status | AI Type | PDF Page | Notes |')
      end

      it 'includes all provider flows from AiUsageRules' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        # Extract provider flows section
        provider_section = markdown[/### Provider Flows.*?### Client Flows/m]

        # Check for some known provider flows
        expect(provider_section).to include('**P1A**')
        expect(provider_section).to include('**P6A**')
        expect(provider_section).to include('**P10-P14**')
        expect(provider_section).to include('**P16**')
        expect(provider_section).to include('**P20**')
      end

      it 'includes all client flows from AiUsageRules' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        # Extract client flows section
        client_section = markdown[/### Client Flows.*?### Using This Mapping/m]

        # Check for some known client flows
        expect(client_section).to include('**C1A**')
        expect(client_section).to include('**C4A**')
        expect(client_section).to include('**C7A**')
      end

      it 'shows YAML key and line number for flows with YAML entries' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        # P1A has YAML entry in our test data
        expect(markdown).to match(/\*\*P1A\*\*.*es\.elisa\.provider\.onboarding\.welcome.*42/)
      end

      it 'shows [MISSING] for flows without YAML entries' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        # Most flows don't have YAML entries in our minimal test data
        expect(markdown).to include('_[MISSING]_')
      end

      it 'marks C2A as Pendiente (pending)' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        # Extract only the Flow-to-YAML Mapping section (section 7)
        mapping_section = markdown[/## 7\. Flow-to-YAML Mapping.*?## 8\./m]

        # C2A should be marked as pending, not missing
        c2a_row = mapping_section.lines.find { |line| line.include?('| **C2A**') }
        expect(c2a_row).to include('📋 **Pendiente**')
        expect(c2a_row).to include('No copy defined in PDF')
      end

      it 'marks flows with AI violations with violation status' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        # Extract only the Flow-to-YAML Mapping section (section 7)
        mapping_section = markdown[/## 7\. Flow-to-YAML Mapping.*?## 8\./m]

        # P10-P14 has a critical violation in our test data
        p10_row = mapping_section.lines.find { |line| line.include?('| **P10-P14**') || line.match?(/\|\s+\|.*P10-P14/) }
        expect(p10_row).to include('🔴 **AI Violation**')
        expect(p10_row).to include('🔴 CRÍTICO')
      end

      it 'marks flows without violations as To Verify' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        # P1A has no violations, should be marked as To Verify
        p1a_row = markdown.lines.find { |line| line.include?('**P1A**') && line.include?('es.elisa.provider') }
        expect(p1a_row).to include('⏳ **To Verify**')
      end

      it 'shows AI type for each flow' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        # Check for various AI types
        expect(markdown).to include('📄 Fixed') # fixed_template
        expect(markdown).to include('🤖 Generation') # generation
        expect(markdown).to include('📥 Extraction') # extraction
        expect(markdown).to include('🧠 Interpretation') # interpretation
      end

      it 'includes model in notes when flow has YAML entry and uses AI' do
        # Create test data with a flow that has YAML entry and uses AI
        ai_flow_inventory = {
          markdown: "# Sample",
          entries: [
            ElisaAudit::MessageEntry.new(
              flow_id: 'P3E',
              yaml_key: 'es.elisa.provider.city_extraction.prompt',
              content: '¿En qué ciudad trabajas?',
              line_number: 100,
              variables: []
            ),
            ElisaAudit::MessageEntry.new(
              flow_id: 'P6A',
              yaml_key: 'es.elisa.provider.bio.generating',
              content: 'Generando tu bio...',
              line_number: 150,
              variables: []
            )
          ],
          stats: { total: 2, provider: 2, client: 0, unknown: 0 }
        }

        result = generator.call(
          yaml_inventory: ai_flow_inventory,
          ai_violations: [],
          template_requirements: []
        )

        markdown = result[:markdown]

        # Extract only the Flow-to-YAML Mapping section (section 7)
        mapping_section = markdown[/## 7\. Flow-to-YAML Mapping.*?## 8\./m]

        # P6A uses Sonnet model - should show in notes
        p6a_rows = mapping_section.lines.select { |line| line.include?('bio.generating') && line.start_with?('|') }
        expect(p6a_rows.any? { |row| row.include?('Model: `sonnet`') }).to be true

        # P3E uses Haiku model - should show in notes
        p3e_rows = mapping_section.lines.select { |line| line.include?('city_extraction') && line.start_with?('|') }
        expect(p3e_rows.any? { |row| row.include?('Model: `haiku`') }).to be true
      end

      it 'marks proactive flows in notes' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        # Extract only the Flow-to-YAML Mapping section (section 7)
        mapping_section = markdown[/## 7\. Flow-to-YAML Mapping.*?## 8\./m]

        # P10-P14 and P16 are proactive
        p10_row = mapping_section.lines.find { |line| (line.include?('| **P10-P14**') || line.match?(/\|\s+\|.*P10-P14/)) && line.start_with?('|') }
        expect(p10_row).to include('Proactive')

        # P1A is not proactive
        p1a_row = mapping_section.lines.find { |line| line.include?('| **P1A**') && line.include?('es.elisa.provider') }
        expect(p1a_row).not_to include('Proactive')
      end

      it 'includes PDF page placeholder for manual filling' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        # All rows should have PDF page placeholder
        flow_table_rows = markdown.lines.select { |line| line.start_with?('| **') || line.include?('| `es.elisa.') }
        flow_table_rows.each do |row|
          expect(row).to include('_[TO FILL]_')
        end
      end

      it 'handles flows with multiple YAML entries' do
        # Add multiple entries for same flow
        multi_entry_inventory = {
          markdown: "# Sample",
          entries: [
            ElisaAudit::MessageEntry.new(
              flow_id: 'P1A',
              yaml_key: 'es.elisa.provider.onboarding.welcome',
              content: 'Message 1',
              line_number: 42,
              variables: []
            ),
            ElisaAudit::MessageEntry.new(
              flow_id: 'P1A',
              yaml_key: 'es.elisa.provider.onboarding.ask_name',
              content: 'Message 2',
              line_number: 45,
              variables: []
            )
          ],
          stats: { total: 2, provider: 2, client: 0, unknown: 0 }
        }

        result = generator.call(
          yaml_inventory: multi_entry_inventory,
          ai_violations: [],
          template_requirements: []
        )

        markdown = result[:markdown]

        # Extract only the Flow-to-YAML Mapping section (section 7)
        mapping_section = markdown[/## 7\. Flow-to-YAML Mapping.*?## 8\./m]

        # Should have two rows for P1A with the actual YAML keys
        p1a_rows = mapping_section.lines.select { |line| line.include?('es.elisa.provider.onboarding') && line.start_with?('|') }
        expect(p1a_rows.count).to eq(2)

        # First row should have flow ID
        expect(p1a_rows[0]).to include('**P1A**')

        # Second row should not repeat flow ID (empty cell)
        expect(p1a_rows[1]).not_to include('**P1A**')
        expect(p1a_rows[1]).to match(/^\|\s+\|/) # Empty first cell
      end

      it 'sorts provider flows numerically with alphabetic suffix' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        # Extract provider section
        provider_section = markdown[/### Provider Flows.*?### Client Flows/m]

        # Extract flow IDs in order they appear
        flow_ids = provider_section.scan(/\*\*P(\d+)([A-Z-]*)\*\*/).map { |num, suffix| "P#{num}#{suffix}" }

        # Should be sorted: P1A, P1B, P2A, ..., P10-P14, ..., P20
        expect(flow_ids).to eq(flow_ids.sort_by do |flow_id|
          match = flow_id.match(/P(\d+)([A-Z-]*)/)
          [match[1].to_i, match[2]]
        end)
      end

      it 'sorts client flows numerically with alphabetic suffix' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        # Extract client section
        client_section = markdown[/### Client Flows.*?### Using This Mapping/m]

        # Extract flow IDs in order they appear
        flow_ids = client_section.scan(/\*\*C(\d+)([A-Z]*)\*\*/).map { |num, suffix| "C#{num}#{suffix}" }

        # Should be sorted: C1A, C1B, C2A, ..., C7A, C7B, C7C, C7D
        expect(flow_ids).to eq(flow_ids.sort_by do |flow_id|
          match = flow_id.match(/C(\d+)([A-Z]*)/)
          [match[1].to_i, match[2]]
        end)
      end
    end

    context 'when generating out-of-scope section' do
      it 'includes out-of-scope section in report' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        expect(markdown).to include('## 9. Pendientes / Fuera de Alcance')
      end

      it 'documents C2A as out of scope' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        expect(markdown).to include('### C2A: Cliente - Consulta de Ciudad/Zona (Pendiente de Definición)')
        expect(markdown).to include('**Status:** ⏸️ **Out of Scope**')
      end

      it 'explains why C2A is out of scope' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        expect(markdown).to include('No copy defined in PDF specification')
        expect(markdown).to include('Per AI_Usage_Rules section 6')
      end

      it 'specifies actions required before C2A implementation' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        expect(markdown).to include('**Action Required Before Implementation:**')
        expect(markdown).to include('UX team must define the official copy for C2A')
        expect(markdown).to include('Copy must be reviewed and approved by product team')
      end

      it 'includes Phase 2 instructions for C2A' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        expect(markdown).to include('**Phase 2 Instruction:**')
        expect(markdown).to include('❌ **DO NOT** attempt to implement C2A in Phase 2')
        expect(markdown).to include('❌ **DO NOT** create messages in `elisa_es.yml` for C2A')
        expect(markdown).to include('❌ **DO NOT** add AI implementation for C2A flows')
        expect(markdown).to include('✅ **WAIT** for official copy specification from UX team')
      end

      it 'references related flows' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        expect(markdown).to include('**Related Flows:**')
        expect(markdown).to include('**C2D**')
        expect(markdown).to include('Similar flow that IS implemented and documented')
      end

      it 'includes summary of out-of-scope flows' do
        result = generator.call(
          yaml_inventory: yaml_inventory,
          ai_violations: ai_violations,
          template_requirements: template_requirements
        )

        markdown = result[:markdown]

        expect(markdown).to include('### Summary')
        expect(markdown).to include('**Total Flows Out of Scope:** 1 (C2A)')
        expect(markdown).to include('**Reason:** Missing copy definition in PDF specification')
        expect(markdown).to include('**Next Steps:** UX team to define and document C2A copy')
      end
    end
  end
end
