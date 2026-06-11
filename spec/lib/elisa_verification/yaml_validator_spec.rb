# frozen_string_literal: true

require "rails_helper"

RSpec.describe ElisaVerification::YamlValidator do
  let(:temp_dir) { Dir.mktmpdir }
  let(:yaml_file_path) { File.join(temp_dir, "test.yml") }

  after do
    FileUtils.remove_entry(temp_dir) if File.exist?(temp_dir)
  end

  describe "#initialize" do
    context "when yaml_file_path is valid" do
      it "creates a validator instance" do
        File.write(yaml_file_path, "es:\n  test: 'value'\n")
        validator = described_class.new(yaml_file_path)

        expect(validator).to be_a(described_class)
        expect(validator.yaml_file_path).to eq(yaml_file_path)
      end
    end

    context "when yaml_file_path is nil" do
      it "raises ArgumentError" do
        expect {
          described_class.new(nil)
        }.to raise_error(ArgumentError, "yaml_file_path cannot be nil or empty")
      end
    end

    context "when yaml_file_path is empty string" do
      it "raises ArgumentError" do
        expect {
          described_class.new("")
        }.to raise_error(ArgumentError, "yaml_file_path cannot be nil or empty")
      end
    end

    context "when file does not exist" do
      it "raises Errno::ENOENT" do
        non_existent_path = File.join(temp_dir, "non_existent.yml")

        expect {
          described_class.new(non_existent_path)
        }.to raise_error(Errno::ENOENT, /File not found/)
      end
    end
  end

  describe "#validate_syntax" do
    context "when YAML syntax is valid" do
      it "returns valid result with no errors" do
        File.write(yaml_file_path, <<~YAML)
          es:
            test:
              message: "Hello World"
              greeting: "Hola"
        YAML

        validator = described_class.new(yaml_file_path)
        result = validator.validate_syntax

        expect(result).to be_a(ElisaVerification::Models::ValidationResult)
        expect(result.valid?).to be true
        expect(result.errors).to be_empty
      end

      it "handles multiline strings" do
        File.write(yaml_file_path, <<~YAML)
          es:
            test:
              message: |
                This is a multiline
                message with proper
                YAML syntax
        YAML

        validator = described_class.new(yaml_file_path)
        result = validator.validate_syntax

        expect(result.valid?).to be true
      end

      it "handles arrays" do
        File.write(yaml_file_path, <<~YAML)
          es:
            test:
              options:
                - "Option 1"
                - "Option 2"
                - "Option 3"
        YAML

        validator = described_class.new(yaml_file_path)
        result = validator.validate_syntax

        expect(result.valid?).to be true
      end

      it "handles interpolation variables" do
        File.write(yaml_file_path, <<~YAML)
          es:
            test:
              message: "Hello %{name}, welcome to %{city}!"
        YAML

        validator = described_class.new(yaml_file_path)
        result = validator.validate_syntax

        expect(result.valid?).to be true
      end
    end

    context "when YAML syntax is invalid" do
      it "detects mapping value errors" do
        File.write(yaml_file_path, <<~YAML)
          es:
            test:
              message: value: invalid
        YAML

        validator = described_class.new(yaml_file_path)
        result = validator.validate_syntax

        expect(result.valid?).to be false
        expect(result.errors).not_to be_empty
        expect(result.errors.first).to include("Line")
      end

      it "detects indentation errors" do
        File.write(yaml_file_path, <<~YAML)
          es:
            test:
           message: "Bad indentation"
        YAML

        validator = described_class.new(yaml_file_path)
        result = validator.validate_syntax

        expect(result.valid?).to be false
        expect(result.errors).not_to be_empty
      end

      it "reports line number in error message" do
        File.write(yaml_file_path, <<~YAML)
          es:
            test:
              message: "Valid"
          bad value without colon
        YAML

        validator = described_class.new(yaml_file_path)
        result = validator.validate_syntax

        expect(result.valid?).to be false
        expect(result.errors.first).to match(/Line \d+/)
      end

      it "includes problem description in error" do
        File.write(yaml_file_path, <<~YAML)
          es:
            test:
              message: value: nested: too: deep
        YAML

        validator = described_class.new(yaml_file_path)
        result = validator.validate_syntax

        expect(result.valid?).to be false
        expect(result.errors.first).to include("Line")
        expect(result.errors.first.length).to be > 10
      end
    end

    context "when file has other parsing errors" do
      it "handles general parsing exceptions" do
        # Create a file with unclosed quote that causes parsing error
        File.write(yaml_file_path, "es:\n  test:\n    message: \"Unclosed quote\n")

        validator = described_class.new(yaml_file_path)
        result = validator.validate_syntax

        expect(result.valid?).to be false
        expect(result.errors).not_to be_empty
      end
    end
  end

  describe "#validate_i18n" do
    context "when Rails can load translations" do
      it "returns valid result" do
        File.write(yaml_file_path, <<~YAML)
          es:
            test:
              message: "Hello World"
        YAML

        validator = described_class.new(yaml_file_path)

        # Mock successful rails runner execution
        allow(Open3).to receive(:capture3).and_return(["", "", instance_double(Process::Status, success?: true)])

        result = validator.validate_i18n

        expect(result.valid?).to be true
        expect(result.errors).to be_empty
      end
    end

    context "when Rails I18n validation fails" do
      it "detects command failure" do
        File.write(yaml_file_path, <<~YAML)
          es:
            test:
              message: "Test"
        YAML

        validator = described_class.new(yaml_file_path)

        # Mock failed rails runner execution
        allow(Open3).to receive(:capture3).and_return(
          ["", "Rails failed to start", instance_double(Process::Status, success?: false, exitstatus: 1)]
        )

        result = validator.validate_i18n

        expect(result.valid?).to be false
        expect(result.errors).not_to be_empty
        expect(result.errors.first).to include("Rails I18n validation failed")
      end

      it "detects YAML syntax errors reported by I18n" do
        File.write(yaml_file_path, <<~YAML)
          es:
            test:
              message: "Test"
        YAML

        validator = described_class.new(yaml_file_path)

        # Mock rails runner output with YAML syntax error
        allow(Open3).to receive(:capture3).and_return(
          ["YAML syntax error in file", "", instance_double(Process::Status, success?: false, exitstatus: 1)]
        )

        result = validator.validate_i18n

        expect(result.valid?).to be false
        expect(result.errors.any? { |e| e.include?("YAML syntax error") }).to be true
      end

      it "detects duplicate key errors" do
        File.write(yaml_file_path, <<~YAML)
          es:
            test:
              message: "Test"
        YAML

        validator = described_class.new(yaml_file_path)

        # Mock rails runner output with duplicate key error
        allow(Open3).to receive(:capture3).and_return(
          ["", "Error: duplicate key found in YAML", instance_double(Process::Status, success?: false, exitstatus: 1)]
        )

        result = validator.validate_i18n

        expect(result.valid?).to be false
        expect(result.errors.any? { |e| e.include?("duplicate keys") }).to be true
      end

      it "detects missing translation keys" do
        File.write(yaml_file_path, <<~YAML)
          es:
            test:
              message: "Test"
        YAML

        validator = described_class.new(yaml_file_path)

        # Mock rails runner output with missing translation
        allow(Open3).to receive(:capture3).and_return(
          ["translation missing: es.some.key", "", instance_double(Process::Status, success?: false, exitstatus: 1)]
        )

        result = validator.validate_i18n

        expect(result.valid?).to be false
        expect(result.errors.any? { |e| e.include?("missing translation") }).to be true
      end

      it "detects conflicting key definitions" do
        File.write(yaml_file_path, <<~YAML)
          es:
            test:
              message: "Test"
        YAML

        validator = described_class.new(yaml_file_path)

        # Mock rails runner output with key conflict
        allow(Open3).to receive(:capture3).and_return(
          ["", "Error: key already exists in translations", instance_double(Process::Status, success?: false, exitstatus: 1)]
        )

        result = validator.validate_i18n

        expect(result.valid?).to be false
        expect(result.errors.any? { |e| e.include?("conflicting key") }).to be true
      end
    end

    context "when command execution fails" do
      it "handles exceptions gracefully" do
        File.write(yaml_file_path, <<~YAML)
          es:
            test:
              message: "Test"
        YAML

        validator = described_class.new(yaml_file_path)

        # Mock exception during command execution
        allow(Open3).to receive(:capture3).and_raise(StandardError.new("Command not found"))

        result = validator.validate_i18n

        expect(result.valid?).to be false
        expect(result.errors.first).to include("Failed to run Rails I18n validation")
      end
    end
  end

  describe "#validate_interpolation" do
    context "when interpolation syntax is correct" do
      it "accepts Rails-style interpolation %{var}" do
        File.write(yaml_file_path, <<~YAML)
          es:
            test:
              message: "Hello %{name}, welcome to %{city}!"
        YAML

        validator = described_class.new(yaml_file_path)
        result = validator.validate_interpolation

        expect(result.valid?).to be true
        expect(result.errors).to be_empty
      end

      it "accepts underscores in variable names" do
        File.write(yaml_file_path, <<~YAML)
          es:
            test:
              message: "Provider: %{provider_name}, Phone: %{phone_number}"
        YAML

        validator = described_class.new(yaml_file_path)
        result = validator.validate_interpolation

        expect(result.valid?).to be true
      end

      it "accepts numbers in variable names" do
        File.write(yaml_file_path, <<~YAML)
          es:
            test:
              message: "Option %{option1} and %{option2}"
        YAML

        validator = described_class.new(yaml_file_path)
        result = validator.validate_interpolation

        expect(result.valid?).to be true
      end

      it "ignores comment lines" do
        File.write(yaml_file_path, <<~YAML)
          es:
            test:
              # This comment has {{invalid}} syntax but should be ignored
              message: "Valid %{name}"
        YAML

        validator = described_class.new(yaml_file_path)
        result = validator.validate_interpolation

        expect(result.valid?).to be true
      end
    end

    context "when interpolation syntax is incorrect" do
      it "detects Mustache-style interpolation {{var}}" do
        File.write(yaml_file_path, <<~YAML)
          es:
            test:
              message: "Hello {{name}}"
        YAML

        validator = described_class.new(yaml_file_path)
        result = validator.validate_interpolation

        expect(result.valid?).to be false
        expect(result.errors.first).to include("Mustache-style")
        expect(result.errors.first).to include("{{name}}")
        expect(result.errors.first).to include("%{name}")
      end

      it "detects JavaScript-style interpolation ${var}" do
        File.write(yaml_file_path, <<~YAML)
          es:
            test:
              message: "Hello ${name}"
        YAML

        validator = described_class.new(yaml_file_path)
        result = validator.validate_interpolation

        expect(result.valid?).to be false
        expect(result.errors.first).to include("JavaScript-style")
        expect(result.errors.first).to include("${name}")
        expect(result.errors.first).to include("%{name}")
      end

      it "detects printf-style interpolation %s" do
        File.write(yaml_file_path, <<~YAML)
          es:
            test:
              message: "Hello %s, you have %d messages"
        YAML

        validator = described_class.new(yaml_file_path)
        result = validator.validate_interpolation

        expect(result.valid?).to be false
        expect(result.errors.any? { |e| e.include?("Printf-style") }).to be true
      end

      it "detects Python-style interpolation {var}" do
        File.write(yaml_file_path, <<~YAML)
          es:
            test:
              message: "Hello {name}"
        YAML

        validator = described_class.new(yaml_file_path)
        result = validator.validate_interpolation

        expect(result.valid?).to be false
        expect(result.errors.first).to include("Python-style")
        expect(result.errors.first).to include("{name}")
        expect(result.errors.first).to include("%{name}")
      end

      it "detects spaces in variable names" do
        File.write(yaml_file_path, <<~YAML)
          es:
            test:
              message: "Hello %{user name}"
        YAML

        validator = described_class.new(yaml_file_path)
        result = validator.validate_interpolation

        expect(result.valid?).to be false
        expect(result.errors.first).to include("contains spaces")
        expect(result.errors.first).to include("underscores")
      end

      it "detects dashes in variable names" do
        File.write(yaml_file_path, <<~YAML)
          es:
            test:
              message: "Hello %{user-name}"
        YAML

        validator = described_class.new(yaml_file_path)
        result = validator.validate_interpolation

        expect(result.valid?).to be false
        expect(result.errors.first).to include("contains dashes")
        expect(result.errors.first).to include("underscores")
      end

      it "detects invalid characters in variable names" do
        File.write(yaml_file_path, <<~YAML)
          es:
            test:
              message: "Hello %{user@name}"
        YAML

        validator = described_class.new(yaml_file_path)
        result = validator.validate_interpolation

        expect(result.valid?).to be false
        expect(result.errors.first).to include("invalid characters")
      end

      it "detects unescaped percent signs followed by letters" do
        File.write(yaml_file_path, <<~YAML)
          es:
            test:
              message: "Discount: %off today"
        YAML

        validator = described_class.new(yaml_file_path)
        result = validator.validate_interpolation

        expect(result.valid?).to be false
        expect(result.errors.first).to include("Unescaped %")
        expect(result.errors.first).to include("%%")
      end

      it "reports line numbers for each error" do
        File.write(yaml_file_path, <<~YAML)
          es:
            test:
              message1: "Hello {{name}}"
              message2: "Welcome ${user}"
              message3: "Discount %s"
        YAML

        validator = described_class.new(yaml_file_path)
        result = validator.validate_interpolation

        expect(result.valid?).to be false
        expect(result.errors.size).to be >= 3
        result.errors.each do |error|
          expect(error).to match(/Line \d+/)
        end
      end
    end

    context "when file reading fails" do
      it "handles exceptions gracefully" do
        File.write(yaml_file_path, "test: value")
        validator = described_class.new(yaml_file_path)

        # Mock file read failure
        allow(File).to receive(:read).and_raise(StandardError.new("Permission denied"))

        result = validator.validate_interpolation

        expect(result.valid?).to be false
        expect(result.errors.first).to include("Failed to validate interpolation syntax")
      end
    end
  end

  describe "#validate_all" do
    context "when all validations pass" do
      it "returns valid result" do
        File.write(yaml_file_path, <<~YAML)
          es:
            test:
              message: "Hello %{name}!"
        YAML

        validator = described_class.new(yaml_file_path)

        # Mock successful I18n validation
        allow(Open3).to receive(:capture3).and_return(["", "", instance_double(Process::Status, success?: true)])

        result = validator.validate_all

        expect(result.valid?).to be true
        expect(result.errors).to be_empty
      end
    end

    context "when syntax validation fails" do
      it "returns early without running other validations" do
        File.write(yaml_file_path, <<~YAML)
          es:
            test:
              message: value: invalid
        YAML

        validator = described_class.new(yaml_file_path)

        # Should not call Open3 for I18n validation if syntax fails
        expect(Open3).not_to receive(:capture3)

        result = validator.validate_all

        expect(result.valid?).to be false
        expect(result.errors).not_to be_empty
      end

      it "returns syntax errors only" do
        File.write(yaml_file_path, <<~YAML)
          es:
            test:
          bad syntax here
        YAML

        validator = described_class.new(yaml_file_path)

        result = validator.validate_all

        expect(result.valid?).to be false
        expect(result.errors.size).to be >= 1
      end
    end

    context "when interpolation validation fails" do
      it "includes interpolation errors in result" do
        File.write(yaml_file_path, <<~YAML)
          es:
            test:
              message: "Hello {{name}}"
        YAML

        validator = described_class.new(yaml_file_path)

        # Mock successful I18n validation
        allow(Open3).to receive(:capture3).and_return(["", "", instance_double(Process::Status, success?: true)])

        result = validator.validate_all

        expect(result.valid?).to be false
        expect(result.errors.any? { |e| e.include?("Mustache-style") }).to be true
      end
    end

    context "when I18n validation fails" do
      it "includes I18n errors in result" do
        File.write(yaml_file_path, <<~YAML)
          es:
            test:
              message: "Valid %{name}"
        YAML

        validator = described_class.new(yaml_file_path)

        # Mock failed I18n validation
        allow(Open3).to receive(:capture3).and_return(
          ["", "duplicate key error", instance_double(Process::Status, success?: false, exitstatus: 1)]
        )

        result = validator.validate_all

        expect(result.valid?).to be false
        expect(result.errors.any? { |e| e.include?("duplicate keys") }).to be true
      end
    end

    context "when multiple validations fail" do
      it "combines all errors" do
        File.write(yaml_file_path, <<~YAML)
          es:
            test:
              message: "Hello {{name}} - %off discount"
        YAML

        validator = described_class.new(yaml_file_path)

        # Mock failed I18n validation
        allow(Open3).to receive(:capture3).and_return(
          ["", "duplicate key error", instance_double(Process::Status, success?: false, exitstatus: 1)]
        )

        result = validator.validate_all

        expect(result.valid?).to be false
        expect(result.errors.size).to be >= 2
        expect(result.errors.any? { |e| e.include?("Mustache-style") }).to be true
        expect(result.errors.any? { |e| e.include?("Unescaped %") }).to be true
      end
    end
  end
end
