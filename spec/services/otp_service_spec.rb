# frozen_string_literal: true

require "rails_helper"

RSpec.describe OtpService do
  let(:phone) { "5212211234567" }
  let(:provider) { instance_double(Provider, id: 1, phone: phone) }
  let(:redis_double) { instance_double(Redis) }

  before do
    stub_const("REDIS", redis_double)
    allow(redis_double).to receive(:setex)
    allow(redis_double).to receive(:get).and_return(nil)
    allow(redis_double).to receive(:del)
    allow(WhatsAppService).to receive(:send_message)
  end

  describe ".generate" do
    context "when phone matches a registered provider" do
      before do
        allow(Provider).to receive(:find_by).with(phone: phone).and_return(provider)
      end

      it "returns success with a masked phone" do
        result = described_class.generate(phone: phone)

        expect(result[:success]).to be true
        expect(result[:masked_phone]).to eq("+52 *** ***4567")
      end

      it "stores a 6-digit OTP in Redis with 10-minute TTL" do
        described_class.generate(phone: phone)

        expect(redis_double).to have_received(:setex).with(
          "otp:#{phone}",
          600,
          a_string_matching(/\A\d{6}\z/)
        )
      end

      it "sends the OTP via WhatsApp" do
        described_class.generate(phone: phone)

        expect(WhatsAppService).to have_received(:send_message).with(
          to: phone,
          message: a_string_matching(/Tu código de acceso a Trato es: \*\d{6}\*/)
        )
      end
    end

    context "when phone does not match any provider" do
      before do
        allow(Provider).to receive(:find_by).with(phone: phone).and_return(nil)
      end

      it "returns failure with :not_found error" do
        result = described_class.generate(phone: phone)

        expect(result[:success]).to be false
        expect(result[:error]).to eq(:not_found)
      end

      it "does not store anything in Redis" do
        described_class.generate(phone: phone)

        expect(redis_double).not_to have_received(:setex)
      end

      it "does not send any WhatsApp message" do
        described_class.generate(phone: phone)

        expect(WhatsAppService).not_to have_received(:send_message)
      end
    end

    context "when phone has non-numeric characters" do
      before do
        allow(Provider).to receive(:find_by).with(phone: phone).and_return(provider)
      end

      it "normalizes the phone before lookup" do
        described_class.generate(phone: "+52 (122) 1123-4567")

        expect(Provider).to have_received(:find_by).with(phone: "5212211234567")
      end
    end
  end

  describe ".verify" do
    let(:stored_code) { "482913" }

    before do
      allow(Provider).to receive(:find_by).with(phone: phone).and_return(provider)
    end

    context "when code matches the stored OTP" do
      before do
        allow(redis_double).to receive(:get).with("otp:#{phone}").and_return(stored_code)
        allow(redis_double).to receive(:get).with("otp_attempts:#{phone}").and_return(nil)
      end

      it "returns success with the provider" do
        result = described_class.verify(phone: phone, code: stored_code)

        expect(result[:success]).to be true
        expect(result[:provider]).to eq(provider)
      end

      it "cleans up the OTP and attempts from Redis" do
        described_class.verify(phone: phone, code: stored_code)

        expect(redis_double).to have_received(:del).with("otp:#{phone}")
        expect(redis_double).to have_received(:del).with("otp_attempts:#{phone}")
      end
    end

    context "when code does not match" do
      before do
        allow(redis_double).to receive(:get).with("otp:#{phone}").and_return(stored_code)
        allow(redis_double).to receive(:get).with("otp_attempts:#{phone}").and_return("0")
      end

      it "returns failure with :invalid error" do
        result = described_class.verify(phone: phone, code: "000000")

        expect(result[:success]).to be false
        expect(result[:error]).to eq(:invalid)
      end

      it "increments the attempt counter in Redis" do
        described_class.verify(phone: phone, code: "000000")

        expect(redis_double).to have_received(:setex).with("otp_attempts:#{phone}", 600, "1")
      end
    end

    context "when OTP has expired (not in Redis)" do
      before do
        allow(redis_double).to receive(:get).with("otp:#{phone}").and_return(nil)
        allow(redis_double).to receive(:get).with("otp_attempts:#{phone}").and_return(nil)
      end

      it "returns failure with :expired error" do
        result = described_class.verify(phone: phone, code: "482913")

        expect(result[:success]).to be false
        expect(result[:error]).to eq(:expired)
      end
    end

    context "when max attempts have been reached" do
      before do
        allow(redis_double).to receive(:get).with("otp_attempts:#{phone}").and_return("5")
      end

      it "returns failure with :max_attempts error" do
        result = described_class.verify(phone: phone, code: stored_code)

        expect(result[:success]).to be false
        expect(result[:error]).to eq(:max_attempts)
      end

      it "does not check the OTP code" do
        described_class.verify(phone: phone, code: stored_code)

        expect(redis_double).not_to have_received(:get).with("otp:#{phone}")
      end
    end

    context "when provider no longer exists after OTP match" do
      before do
        allow(redis_double).to receive(:get).with("otp:#{phone}").and_return(stored_code)
        allow(redis_double).to receive(:get).with("otp_attempts:#{phone}").and_return(nil)
        allow(Provider).to receive(:find_by).with(phone: phone).and_return(nil)
      end

      it "returns failure with :not_found error" do
        result = described_class.verify(phone: phone, code: stored_code)

        expect(result[:success]).to be false
        expect(result[:error]).to eq(:not_found)
      end
    end
  end
end
