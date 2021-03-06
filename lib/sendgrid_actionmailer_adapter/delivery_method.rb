# frozen_string_literal: true

require 'sendgrid/client'
require_relative 'configuration'
require_relative 'converter'
require_relative 'errors'

module SendGridActionMailerAdapter
  class DeliveryMethod
    attr_reader :settings

    # Initialize this instance.
    #
    # This method is expected to be called from Mail::Message class.
    #
    # @params [Hash] settings settings parameters which you want to override.
    # @options settings [String] :api_key Your SendGrid Web API key.
    # @options settings [String] :host Base host FQDN of API endpoint.
    # @options settings [Hash] :request_headers Request headers which you want to override.
    # @options settings [String] :version API version string, eg: 'v3'.
    # @options settings [Integer] :retry_max_count Count for retry, Default is 0(Do not retry).
    # @options settings [Integer, Float] :retry_wait_sec Wait seconds for next retry, Default is 1.
    def initialize(settings)
      @settings = ::SendGridActionMailerAdapter::Configuration.settings.merge(settings)
    end

    # Deliver a mail via SendGrid Web API.
    #
    # This method is called from Mail::Message#deliver!.
    #
    # @param [Mail::Message] mail Mail::Message object which you want to send.
    # @raise [SendGridActionMailerAdapter::ValidationError] when validation error occurred.
    # @raise [SendGridActionMailerAdapter::ApiError] when SendGrid Web API returns error response.
    def deliver!(mail)
      sendgrid_mail = ::SendGridActionMailerAdapter::Converter.to_sendgrid_mail(mail)
      body = sendgrid_mail.to_json
      client = ::SendGrid::API.new(@settings[:sendgrid]).client.mail._('send')

      with_retry(@settings[:retry]) do
        response = client.post(request_body: body)
        handle_response!(response)
      end
    end

    private

    def with_retry(max_count:, wait_seconds:)
      tryable_count = max_count + 1
      begin
        tryable_count -= 1
        yield
      rescue ::SendGridActionMailerAdapter::ApiClientError => _e
        raise
      rescue => _e
        if tryable_count > 0
          sleep(wait_seconds)
          retry
        end
        raise
      end
    end

    # @see https://sendgrid.com/docs/API_Reference/Web_API_v3/Mail/errors.html
    def handle_response!(response)
      case response.status_code.to_i
      when (200..299)
        response
      when (400..499)
        raise ::SendGridActionMailerAdapter::ApiClientError, response
      else
        raise ::SendGridActionMailerAdapter::ApiUnexpectedError, response
      end
    end
  end
end
