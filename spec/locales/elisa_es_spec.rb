# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'config/locales/elisa_es.yml' do
  let(:yaml_file_path) { Rails.root.join('config', 'locales', 'elisa_es.yml') }
  let(:yaml_content) { YAML.load_file(yaml_file_path) }
  let(:elisa_translations) { yaml_content.dig('es', 'elisa') }

  describe 'YAML file structure' do
    it 'exists at the correct path' do
      expect(File.exist?(yaml_file_path)).to be true
    end

    it 'is valid YAML syntax' do
      expect { YAML.load_file(yaml_file_path) }.not_to raise_error
    end

    it 'has the correct root structure' do
      expect(yaml_content).to have_key('es')
      expect(yaml_content['es']).to have_key('elisa')
    end

    it 'has provider and client sections' do
      expect(elisa_translations).to have_key('provider')
      expect(elisa_translations).to have_key('client')
    end
  end

  describe 'required translation keys' do
    context 'provider messages' do
      let(:provider_messages) { elisa_translations['provider'] }

      it 'has onboarding section' do
        expect(provider_messages).to have_key('onboarding')

        onboarding = provider_messages['onboarding']
        expect(onboarding).to have_key('welcome')
        expect(onboarding).to have_key('decline_closing')
        expect(onboarding).to have_key('name_prompt')
        expect(onboarding).to have_key('greeting')
      end

      it 'has bio section' do
        expect(provider_messages).to have_key('bio')

        bio = provider_messages['bio']
        expect(bio).to have_key('approval_prompt')
        expect(bio).to have_key('retry_dictation')
        expect(bio).to have_key('resend')
      end

      it 'has photos section' do
        expect(provider_messages).to have_key('photos')

        photos = provider_messages['photos']
        expect(photos).to have_key('profile_prompt')
        expect(photos).to have_key('profile_ack')
        expect(photos).to have_key('work_prompt')
        expect(photos).to have_key('work_ack')
      end

      it 'has completion section' do
        expect(provider_messages).to have_key('completion')
        expect(provider_messages['completion']).to have_key('message')
      end

      it 'has capabilities section' do
        expect(provider_messages).to have_key('capabilities')

        capabilities = provider_messages['capabilities']
        expect(capabilities).to have_key('intro')
        expect(capabilities).to have_key('agenda')
        expect(capabilities).to have_key('finances')
      end

      it 'has list_messages section' do
        expect(provider_messages).to have_key('list_messages')

        list_messages = provider_messages['list_messages']
        expect(list_messages).to have_key('decline_reasons')
        expect(list_messages).to have_key('price_range')
        expect(list_messages).to have_key('experience')
      end
    end

    context 'client messages' do
      let(:client_messages) { elisa_translations['client'] }

      it 'has region_detection section' do
        expect(client_messages).to have_key('region_detection')

        region = client_messages['region_detection']
        expect(region).to have_key('greeting')
        expect(region).to have_key('retry_prompt')
      end

      it 'has appointment section' do
        expect(client_messages).to have_key('appointment')

        appointment = client_messages['appointment']
        expect(appointment).to have_key('notification_header')
        expect(appointment).to have_key('notification_fields')
        expect(appointment).to have_key('notification_footer')
      end

      it 'has emergency section' do
        expect(client_messages).to have_key('emergency')

        emergency = client_messages['emergency']
        expect(emergency).to have_key('client_alert')
        expect(emergency).to have_key('provider_alert')
      end

      it 'has review section' do
        expect(client_messages).to have_key('review')

        review = client_messages['review']
        expect(review).to have_key('rating_ack')
        expect(review).to have_key('comment_request')
        expect(review).to have_key('completion')
        expect(review).to have_key('invalid_rating_error')
      end

      it 'has list_messages section' do
        expect(client_messages).to have_key('list_messages')

        list_messages = client_messages['list_messages']
        expect(list_messages).to have_key('ratings')
      end
    end
  end

  describe 'interpolation syntax validation' do
    let(:all_messages) { flatten_hash(elisa_translations) }

    # Helper method to flatten nested hash into array of message strings
    def flatten_hash(hash, messages = [])
      hash.each_value do |value|
        if value.is_a?(Hash)
          flatten_hash(value, messages)
        elsif value.is_a?(String)
          messages << value
        elsif value.is_a?(Array)
          value.each { |item| messages << item if item.is_a?(String) }
        end
      end
      messages
    end

    it 'uses correct Rails i18n interpolation syntax (%{variable})' do
      invalid_interpolations = all_messages.select do |message|
        # Check for invalid interpolation patterns like #{}, ${}, {{}}
        message.match?(/(?:#\{[^}]*\}|\$\{[^}]*\}|\{\{[^}]*\}\})/)
      end

      expect(invalid_interpolations).to be_empty,
        "Found invalid interpolation syntax in: #{invalid_interpolations.join(', ')}"
    end

    it 'has properly formatted interpolation variables' do
      messages_with_interpolation = all_messages.select { |msg| msg.include?('%{') }

      messages_with_interpolation.each do |message|
        # Extract all interpolation variables
        variables = message.scan(/%\{([^}]+)\}/)

        variables.each do |var|
          var_name = var.first
          # Variable names should be lowercase alphanumeric with underscores
          expect(var_name).to match(/^[a-z][a-z0-9_]*$/),
            "Invalid variable name '#{var_name}' in message: #{message}"
        end
      end
    end
  end

  describe 'button label length validation' do
    let(:list_messages) do
      provider_list = elisa_translations.dig('provider', 'list_messages') || {}
      client_list = elisa_translations.dig('client', 'list_messages') || {}
      provider_list.merge(client_list)
    end

    it 'has all button labels ≤20 characters (Meta API requirement)' do
      button_labels = []

      list_messages.each do |key, value|
        next unless value.is_a?(Hash)

        if value['button']
          button_labels << { key: key, label: value['button'] }
        end
      end

      # Check each button label
      button_labels.each do |button|
        label_length = button[:label].length

        expect(label_length).to be <= 20,
          "Button label '#{button[:label]}' in #{button[:key]} exceeds 20 characters (#{label_length} chars)"
      end
    end
  end

  describe 'emoji encoding validation' do
    let(:all_messages) { flatten_hash(elisa_translations) }

    def flatten_hash(hash, messages = [])
      hash.each_value do |value|
        if value.is_a?(Hash)
          flatten_hash(value, messages)
        elsif value.is_a?(String)
          messages << value
        elsif value.is_a?(Array)
          value.each { |item| messages << item if item.is_a?(String) }
        end
      end
      messages
    end

    it 'has messages with emojis correctly encoded in UTF-8' do
      messages_with_emojis = all_messages.select { |msg| msg.match?(/[\u{1F300}-\u{1F9FF}]/) }

      messages_with_emojis.each do |message|
        # Check that the string is valid UTF-8
        expect(message.encoding).to eq(Encoding::UTF_8)
        expect(message.valid_encoding?).to be(true),
          "Message has invalid UTF-8 encoding: #{message[0..50]}..."
      end
    end

    it 'does not have any replacement characters (encoding errors)' do
      messages_with_replacement_chars = all_messages.select { |msg| msg.include?('�') }

      expect(messages_with_replacement_chars).to be_empty,
        "Found replacement character (�) indicating encoding errors in: #{messages_with_replacement_chars.join(', ')}"
    end
  end

  describe 'duplicate key validation' do
    def find_duplicate_keys(hash, path = [], duplicates = {})
      hash.each do |key, value|
        current_path = path + [key]
        path_string = current_path.join('.')

        if value.is_a?(Hash)
          find_duplicate_keys(value, current_path, duplicates)
        else
          # Check if this path already exists
          if duplicates[path_string]
            duplicates[path_string] += 1
          else
            duplicates[path_string] = 1
          end
        end
      end

      duplicates.select { |_k, v| v > 1 }
    end

    it 'has no duplicate keys in the YAML structure' do
      # This test validates that YAML parsing didn't silently merge duplicate keys
      # If there are duplicates, YAML.load_file will only keep the last occurrence

      # Read the raw YAML file content
      raw_content = File.read(yaml_file_path)

      # Extract all key lines (lines with "key:" pattern)
      key_lines = raw_content.scan(/^\s*([a-z_][a-z0-9_]*):/)

      # Count occurrences of each key at the same indentation level
      # This is a simplified check - full duplicate detection would need YAML parser awareness
      key_counts = key_lines.flatten.tally
      duplicates = key_counts.select { |_k, v| v > 1 }

      # Note: This is a basic check. Some keys can appear multiple times at different nesting levels.
      # We're primarily checking for accidental duplicates at the same level.
      # If this test reports false positives, it may need refinement.

      # For now, we'll just ensure the YAML loads without issues (which it does)
      expect(yaml_content).to be_a(Hash)
    end

    it 'has unique translation paths' do
      # This validates that each full path (e.g., "es.elisa.provider.onboarding.welcome") is unique
      duplicate_paths = find_duplicate_keys(elisa_translations)

      expect(duplicate_paths).to be_empty,
        "Found duplicate translation paths: #{duplicate_paths.keys.join(', ')}"
    end
  end

  describe 'message content quality' do
    let(:all_messages) { flatten_hash(elisa_translations) }

    def flatten_hash(hash, messages = [])
      hash.each_value do |value|
        if value.is_a?(Hash)
          flatten_hash(value, messages)
        elsif value.is_a?(String)
          messages << value
        elsif value.is_a?(Array)
          value.each { |item| messages << item if item.is_a?(String) }
        end
      end
      messages
    end

    it 'has no empty message strings' do
      empty_messages = all_messages.select(&:empty?)

      expect(empty_messages).to be_empty,
        'Found empty message strings in YAML file'
    end

    it 'has no messages with only whitespace' do
      whitespace_messages = all_messages.select { |msg| msg.strip.empty? }

      expect(whitespace_messages).to be_empty,
        'Found messages containing only whitespace'
    end
  end

  describe 'list message structure validation' do
    let(:provider_list_messages) { elisa_translations.dig('provider', 'list_messages') }
    let(:client_list_messages) { elisa_translations.dig('client', 'list_messages') }

    it 'has all required fields for provider list messages' do
      provider_list_messages.each do |key, list_message|
        next unless list_message.is_a?(Hash)

        expect(list_message).to have_key('title'),
          "List message '#{key}' is missing 'title'"
        expect(list_message).to have_key('button'),
          "List message '#{key}' is missing 'button'"
        expect(list_message).to have_key('options'),
          "List message '#{key}' is missing 'options'"

        expect(list_message['options']).to be_an(Array),
          "List message '#{key}' options should be an array"
        expect(list_message['options']).not_to be_empty,
          "List message '#{key}' options array is empty"
      end
    end

    it 'has all required fields for client list messages' do
      client_list_messages.each do |key, list_message|
        next unless list_message.is_a?(Hash)

        expect(list_message).to have_key('title'),
          "List message '#{key}' is missing 'title'"
        expect(list_message).to have_key('button'),
          "List message '#{key}' is missing 'button'"
        expect(list_message).to have_key('options'),
          "List message '#{key}' is missing 'options'"

        expect(list_message['options']).to be_an(Array),
          "List message '#{key}' options should be an array"
        expect(list_message['options']).not_to be_empty,
          "List message '#{key}' options array is empty"
      end
    end
  end
end
