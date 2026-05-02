# frozen_string_literal: true

require "rails_helper"

RSpec.describe Assistants::SocialMediaService do
  let(:provider) do
    instance_double(
      Provider,
      id: 1,
      name: "Miguel García",
      phone: "5212211234567",
      city: "Veracruz",
      facebook_token: "fb_token_123",
      instagram_token: nil,
      photos: photos_relation,
      provider_categories: categories_relation
    )
  end

  let(:photos_relation) { double("photos_relation") }
  let(:categories_relation) { double("categories_relation") }
  let(:photo) { instance_double(Photo, id: 10, url: "https://trato-photos.s3.amazonaws.com/photos/panel.jpg") }

  before do
    allow(categories_relation).to receive(:pluck).with(:slug).and_return(["electricista"])
    allow(categories_relation).to receive(:pluck).with(:name).and_return(["Electricista"])
    allow(WhatsAppService).to receive(:send_message).and_return(true)
  end

  describe "initiate_social_post" do
    let(:action_data) do
      { "photo_url" => "https://trato-photos.s3.amazonaws.com/photos/panel.jpg", "description" => "Panel eléctrico" }
    end

    context "when provider has facebook_token" do
      before do
        allow(photos_relation).to receive(:create!).and_return(photo)
      end

      it "creates a Photo record" do
        described_class.call(provider: provider, action: "initiate_social_post", action_data: action_data)

        expect(photos_relation).to have_received(:create!).with(
          hash_including(
            url: "https://trato-photos.s3.amazonaws.com/photos/panel.jpg",
            caption: "Panel eléctrico",
            category_tags: ["electricista"]
          )
        )
      end

      it "returns the created photo" do
        result = described_class.call(provider: provider, action: "initiate_social_post", action_data: action_data)

        expect(result).to eq(photo)
      end
    end

    context "when provider has no facebook_token" do
      let(:provider) do
        instance_double(
          Provider,
          id: 1,
          name: "Miguel García",
          phone: "5212211234567",
          facebook_token: nil,
          instagram_token: nil,
          photos: photos_relation,
          provider_categories: categories_relation
        )
      end

      before do
        allow(photos_relation).to receive(:create!).and_return(photo)
        allow(REDIS).to receive(:setex)
        allow(SecureRandom).to receive(:hex).with(16).and_return("abc123def456ghi7")
      end

      it "creates the photo record" do
        described_class.call(provider: provider, action: "initiate_social_post", action_data: action_data)

        expect(photos_relation).to have_received(:create!)
      end

      it "stores a connect token in Redis with 10-minute TTL" do
        described_class.call(provider: provider, action: "initiate_social_post", action_data: action_data)

        expect(REDIS).to have_received(:setex).with(
          "facebook_connect:abc123def456ghi7",
          600,
          provider.id
        )
      end

      it "sends the Facebook connect link via WhatsApp" do
        described_class.call(provider: provider, action: "initiate_social_post", action_data: action_data)

        expect(WhatsAppService).to have_received(:send_message).with(
          to: provider.phone,
          message: a_string_matching(%r{/connect/facebook\?token=abc123def456ghi7})
        )
      end

      it "returns nil when sending connect link" do
        result = described_class.call(provider: provider, action: "initiate_social_post", action_data: action_data)

        expect(result).to be_nil
      end
    end
  end

  describe "generate_caption" do
    let(:action_data) do
      { "photo_url" => "https://trato-photos.s3.amazonaws.com/photos/panel.jpg", "description" => "Panel eléctrico residencial" }
    end

    let(:claude_response) do
      {
        "message" => "¡Trabajo terminado! 🔌 Panel eléctrico instalado en Veracruz. #Electricista",
        "action" => "none",
        "action_data" => {},
        "new_stage" => nil,
        "updated_context" => {},
        "should_save_message" => false,
        "intent" => "caption_generated"
      }
    end

    before do
      allow(ClaudeService).to receive(:call).and_return(claude_response)
    end

    it "calls ClaudeService with sonnet model" do
      described_class.call(provider: provider, action: "generate_caption", action_data: action_data)

      expect(ClaudeService).to have_received(:call).with(
        model: :sonnet,
        system_prompt: a_string_matching(/pies de foto/),
        user_message: a_string_matching(/Panel eléctrico residencial/),
        context: {}
      )
    end

    it "includes provider name in the caption request" do
      described_class.call(provider: provider, action: "generate_caption", action_data: action_data)

      expect(ClaudeService).to have_received(:call).with(
        hash_including(user_message: a_string_matching(/Miguel García/))
      )
    end

    it "includes provider city in the caption request" do
      described_class.call(provider: provider, action: "generate_caption", action_data: action_data)

      expect(ClaudeService).to have_received(:call).with(
        hash_including(user_message: a_string_matching(/Veracruz/))
      )
    end

    it "returns the Claude response" do
      result = described_class.call(provider: provider, action: "generate_caption", action_data: action_data)

      expect(result).to eq(claude_response)
    end
  end

  describe "approve_caption" do
    let(:action_data) do
      { "photo_id" => "10", "caption" => "¡Trabajo terminado! 🔌 #Electricista" }
    end

    let(:published_post) { instance_double(SocialPost, status: "published", platform: "facebook") }

    before do
      allow(photos_relation).to receive(:find_by).with(id: "10").and_return(photo)
      allow(SocialService).to receive(:publish).and_return(published_post)
    end

    context "when publish succeeds" do
      it "calls SocialService.publish with correct params" do
        described_class.call(provider: provider, action: "approve_caption", action_data: action_data)

        expect(SocialService).to have_received(:publish).with(
          provider: provider,
          photo: photo,
          caption: "¡Trabajo terminado! 🔌 #Electricista"
        )
      end

      it "sends success notification via WhatsApp" do
        described_class.call(provider: provider, action: "approve_caption", action_data: action_data)

        expect(WhatsAppService).to have_received(:send_message).with(
          to: provider.phone,
          message: a_string_matching(/Publicado en Facebook/)
        )
      end

      it "returns the social post" do
        result = described_class.call(provider: provider, action: "approve_caption", action_data: action_data)

        expect(result).to eq(published_post)
      end
    end

    context "when publish fails" do
      let(:failed_post) { instance_double(SocialPost, status: "failed", platform: "facebook") }

      before do
        allow(SocialService).to receive(:publish).and_return(failed_post)
      end

      it "sends failure notification via WhatsApp" do
        described_class.call(provider: provider, action: "approve_caption", action_data: action_data)

        expect(WhatsAppService).to have_received(:send_message).with(
          to: provider.phone,
          message: a_string_matching(/problema al publicar/)
        )
      end
    end

    context "when photo is not found" do
      before do
        allow(photos_relation).to receive(:find_by).with(id: "10").and_return(nil)
      end

      it "returns nil without publishing" do
        result = described_class.call(provider: provider, action: "approve_caption", action_data: action_data)

        expect(result).to be_nil
        expect(SocialService).not_to have_received(:publish)
      end
    end

    context "when both platforms are published" do
      let(:published_post) { instance_double(SocialPost, status: "published", platform: "both") }

      it "mentions both platforms in the success message" do
        described_class.call(provider: provider, action: "approve_caption", action_data: action_data)

        expect(WhatsAppService).to have_received(:send_message).with(
          to: provider.phone,
          message: a_string_matching(/Facebook e Instagram/)
        )
      end
    end
  end
end
