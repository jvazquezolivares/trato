# frozen_string_literal: true

require "rails_helper"

RSpec.describe Assistants::ConversationPersistenceService do
  let(:conversation) { instance_double(Conversation, id: 1, messages: messages_relation) }
  let(:messages_relation) { double("messages_relation") }

  before do
    allow(messages_relation).to receive(:create!).and_return(true)
    allow(conversation).to receive(:update!).and_return(true)
  end

  describe ".call" do
    context "when should_save_message is true" do
      let(:response) do
        {
          "message" => "Registrado ✅",
          "should_save_message" => true,
          "intent" => "job_registered",
          "new_stage" => "active",
          "updated_context" => { "last_action" => "job" }
        }
      end

      it "persists the inbound message" do
        described_class.call(conversation: conversation, response: response, inbound_body: "Terminé un trabajo")

        expect(messages_relation).to have_received(:create!).with(
          hash_including(
            direction: "inbound",
            body: "Terminé un trabajo",
            intent: "job_registered",
            processed: true
          )
        )
      end

      it "persists the outbound reply" do
        described_class.call(conversation: conversation, response: response, inbound_body: "Terminé un trabajo")

        expect(messages_relation).to have_received(:create!).with(
          hash_including(
            direction: "outbound",
            body: "Registrado ✅",
            intent: "job_registered",
            processed: true
          )
        )
      end

      it "includes media_url when provided" do
        described_class.call(
          conversation: conversation, response: response,
          inbound_body: "Foto", media_url: "https://example.com/photo.jpg"
        )

        expect(messages_relation).to have_received(:create!).with(
          hash_including(media_url: "https://example.com/photo.jpg")
        )
      end
    end

    context "when should_save_message is false" do
      let(:response) do
        {
          "message" => "Ok 👍",
          "should_save_message" => false,
          "intent" => nil,
          "new_stage" => nil,
          "updated_context" => nil
        }
      end

      it "does not persist any messages" do
        described_class.call(conversation: conversation, response: response, inbound_body: "ok")

        expect(messages_relation).not_to have_received(:create!)
      end
    end

    context "when outbound message is blank" do
      let(:response) do
        {
          "message" => "",
          "should_save_message" => true,
          "intent" => "client_first_contact",
          "new_stage" => nil,
          "updated_context" => nil
        }
      end

      it "persists only the inbound message" do
        described_class.call(conversation: conversation, response: response, inbound_body: "Hola")

        expect(messages_relation).to have_received(:create!).once
        expect(messages_relation).to have_received(:create!).with(
          hash_including(direction: "inbound")
        )
      end
    end

    it "always updates conversation with last_message_at" do
      response = { "message" => "Ok", "should_save_message" => false, "new_stage" => nil, "updated_context" => nil }

      described_class.call(conversation: conversation, response: response, inbound_body: "ok")

      expect(conversation).to have_received(:update!).with(hash_including(:last_message_at))
    end

    it "updates stage when new_stage is present" do
      response = { "message" => "Ok", "should_save_message" => false, "new_stage" => "scheduling", "updated_context" => nil }

      described_class.call(conversation: conversation, response: response, inbound_body: "ok")

      expect(conversation).to have_received(:update!).with(hash_including(stage: "scheduling"))
    end

    it "updates context when updated_context is present" do
      response = { "message" => "Ok", "should_save_message" => false, "new_stage" => nil, "updated_context" => { "step" => "2" } }

      described_class.call(conversation: conversation, response: response, inbound_body: "ok")

      expect(conversation).to have_received(:update!).with(hash_including(context: { "step" => "2" }))
    end
  end
end
