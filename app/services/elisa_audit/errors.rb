# frozen_string_literal: true

module ElisaAudit
  # Custom error for YAML parsing issues
  class YamlParseError < StandardError; end

  # Custom error for service file analysis issues
  class ServiceAnalysisError < StandardError; end

  # Custom error for report generation issues
  class ReportGenerationError < StandardError; end
end
