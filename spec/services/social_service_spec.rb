# frozen_string_literal: true

require "rails_helper"
require "webmock/rspec"

RSpec.describe SocialService do
  let(:provider) do
    instance_double(
      Provider,
      id: 1,
      name: "Miguel García",
      phone: "5212211234567",
      facebook_token: "fb_token_123",
      instagram_token: nil,
      social_posts: social_posts_relation
    )
  end

  let(:photo) do
    instance_double(
      Photo,
      id: 10,
      url: "https://trato-photos.s3.amazonaws.com/photos/panel-electrico.jpg"
    )
  end

  let(:social_posts_relation) { double("social_posts_relation") }
  let(:caption) { "¡Trabajo terminado! 🔌 Panel eléctrico instalado. #Electricista #Veracruz" }

  before do
    allow(social_posts_relation).to receive(:create!).and_return(
      instance_double(SocialPost, status: "published", platform: "facebook")
    )
  end

  describe ".publish" do
    context "when provider has no facebook_token" do
      let(:provider) do
        instance_double(
          Provider,
          id: 1,
          facebook_token: nil,
          instagram_token: nil,
          social_posts: social_posts_relation
        )
      end

      before do
        allow(social_posts_relation).to receive(:create!).and_return(
          instance_double(SocialPost, status: "failed", platform: "facebook")
        )
      end

      it "creates a failed SocialPost" do
        described_class.publish(provider: provider, photo: photo, caption: caption)

        expect(social_posts_relation).to have_received(:create!).with(
          hash_including(
            status: "failed",
            error_message: "El proveedor no tiene token de Facebook"
          )
        )
      end
    end

    context "when provider has facebook_token only" do
      let(:page_accounts_response) do
        double("response",
          success?: true,
          parsed_response: { "data" => [ { "id" => "page_123" } ] })
      end

      let(:publish_response) do
        double("response", success?: true, parsed_response: { "id" => "post_456" })
      end

      before do
        stub_request(:get, %r{graph\.facebook\.com/v19\.0/me/accounts})
          .to_return(
            status: 200,
            body: { "data" => [ { "id" => "page_123" } ] }.to_json,
            headers: { "Content-Type" => "application/json" }
          )

        stub_request(:post, %r{graph\.facebook\.com/v19\.0/page_123/photos})
          .to_return(
            status: 200,
            body: { "id" => "post_456" }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "publishes to Facebook and creates a published SocialPost" do
        described_class.publish(provider: provider, photo: photo, caption: caption)

        expect(social_posts_relation).to have_received(:create!).with(
          hash_including(
            photo: photo,
            caption_generated: caption,
            platform: "facebook",
            status: "published"
          )
        )
      end
    end

    context "when provider has both facebook and instagram tokens" do
      let(:provider) do
        instance_double(
          Provider,
          id: 1,
          facebook_token: "fb_token_123",
          instagram_token: "ig_token_456",
          social_posts: social_posts_relation
        )
      end

      before do
        stub_request(:get, %r{graph\.facebook\.com/v19\.0/me/accounts})
          .to_return(
            status: 200,
            body: { "data" => [ { "id" => "page_123" } ] }.to_json,
            headers: { "Content-Type" => "application/json" }
          )

        stub_request(:post, %r{graph\.facebook\.com/v19\.0/page_123/photos})
          .to_return(
            status: 200,
            body: { "id" => "post_456" }.to_json,
            headers: { "Content-Type" => "application/json" }
          )

        stub_request(:get, %r{graph\.facebook\.com/v19\.0/page_123\?})
          .to_return(
            status: 200,
            body: { "instagram_business_account" => { "id" => "ig_account_789" } }.to_json,
            headers: { "Content-Type" => "application/json" }
          )

        stub_request(:post, %r{graph\.facebook\.com/v19\.0/ig_account_789/media$})
          .to_return(
            status: 200,
            body: { "id" => "container_001" }.to_json,
            headers: { "Content-Type" => "application/json" }
          )

        stub_request(:post, %r{graph\.facebook\.com/v19\.0/ig_account_789/media_publish})
          .to_return(
            status: 200,
            body: { "id" => "ig_post_002" }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "publishes to both platforms" do
        described_class.publish(provider: provider, photo: photo, caption: caption)

        expect(social_posts_relation).to have_received(:create!).with(
          hash_including(platform: "both", status: "published")
        )
      end
    end

    context "when Facebook publish fails" do
      before do
        stub_request(:get, %r{graph\.facebook\.com/v19\.0/me/accounts})
          .to_return(
            status: 200,
            body: { "data" => [ { "id" => "page_123" } ] }.to_json,
            headers: { "Content-Type" => "application/json" }
          )

        stub_request(:post, %r{graph\.facebook\.com/v19\.0/page_123/photos})
          .to_return(
            status: 400,
            body: { "error" => { "message" => "Invalid photo URL" } }.to_json,
            headers: { "Content-Type" => "application/json" }
          )

        allow(social_posts_relation).to receive(:create!).and_return(
          instance_double(SocialPost, status: "failed", platform: "facebook")
        )
      end

      it "creates a failed SocialPost with error message" do
        described_class.publish(provider: provider, photo: photo, caption: caption)

        expect(social_posts_relation).to have_received(:create!).with(
          hash_including(
            status: "failed",
            error_message: a_string_matching(/Facebook/)
          )
        )
      end
    end

    context "when page ID cannot be fetched" do
      before do
        stub_request(:get, %r{graph\.facebook\.com/v19\.0/me/accounts})
          .to_return(
            status: 401,
            body: { "error" => { "message" => "Invalid token" } }.to_json,
            headers: { "Content-Type" => "application/json" }
          )

        allow(social_posts_relation).to receive(:create!).and_return(
          instance_double(SocialPost, status: "failed", platform: "facebook")
        )
      end

      it "creates a failed SocialPost" do
        described_class.publish(provider: provider, photo: photo, caption: caption)

        expect(social_posts_relation).to have_received(:create!).with(
          hash_including(
            status: "failed",
            error_message: a_string_matching(/página de Facebook/)
          )
        )
      end
    end
  end
end
