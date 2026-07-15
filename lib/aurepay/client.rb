# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'

module AurePay
  # Erro tipado da API AurePay.
  class Error < StandardError
    attr_reader :code, :details, :status_code

    def initialize(message, code: nil, details: nil, status_code: 0)
      super(message)
      @code = code
      @details = details
      @status_code = status_code
    end
  end

  # Transporte HTTP autenticado com retry em 429.
  class HttpTransport
    def initialize(api_key:, api_secret:, base_url:, max_retries: 2)
      @api_key = api_key
      @api_secret = api_secret
      @base_url = base_url.sub(%r{/\z}, '')
      @max_retries = max_retries
    end

    # Executa requisição autenticada e desempacota o envelope `data`.
    def request(method, path, body: nil, extra_headers: {})
      url = URI("#{@base_url}/#{path.sub(%r{\A/}, '')}")
      attempt = 0

      loop do
        attempt += 1
        http = Net::HTTP.new(url.host, url.port)
        http.use_ssl = url.scheme == 'https'

        verb = method.to_s.upcase
        request_class = {
          'GET' => Net::HTTP::Get,
          'POST' => Net::HTTP::Post,
          'PUT' => Net::HTTP::Put,
          'PATCH' => Net::HTTP::Patch,
          'DELETE' => Net::HTTP::Delete
        }.fetch(verb)

        request = request_class.new(url)
        request['X-Api-Key'] = @api_key
        request['X-Api-Secret'] = @api_secret
        request['Accept'] = 'application/json'
        request['Content-Type'] = 'application/json'
        extra_headers.each { |key, value| request[key] = value }
        request.body = JSON.generate(body) unless body.nil?

        response = http.request(request)
        status = response.code.to_i
        raw = response.body.to_s
        decoded = raw.empty? ? nil : JSON.parse(raw)

        if status == 429 && attempt <= @max_retries + 1
          sleep([1, (response['Retry-After'] || '1').to_i].max)
          next
        end

        if status >= 400
          error = decoded.is_a?(Hash) ? decoded['error'] : nil
          message = error.is_a?(Hash) ? (error['message'] || 'Request failed.') : 'Request failed.'
          raise Error.new(
            message.to_s,
            code: error.is_a?(Hash) ? error['code'] : nil,
            details: error.is_a?(Hash) ? error['details'] : nil,
            status_code: status
          )
        end

        return decoded['data'] if decoded.is_a?(Hash) && decoded.key?('data')

        return decoded
      end
    end
  end

  # Recurso CRUD genérico (list/create/get/update/delete).
  class CrudResource
    def initialize(http, base_path)
      @http = http
      @base_path = base_path
    end

    def list(query = {})
      path = @base_path
      unless query.nil? || query.empty?
        path = "#{path}?#{URI.encode_www_form(query)}"
      end
      @http.request('Get', path)
    end

    def create(payload, idempotency_key: nil)
      headers = idempotency_key ? { 'Idempotency-Key' => idempotency_key } : {}
      @http.request('Post', @base_path, body: payload, extra_headers: headers)
    end

    def get(id)
      @http.request('Get', "#{@base_path}/#{URI.encode_www_form_component(id)}")
    end

    def update(id, payload)
      @http.request('Put', "#{@base_path}/#{URI.encode_www_form_component(id)}", body: payload)
    end

    def delete(id)
      @http.request('Delete', "#{@base_path}/#{URI.encode_www_form_component(id)}")
    end
  end

  # Empresa autenticada e saldo.
  class Company
    def initialize(http)
      @http = http
    end

    # Dados da empresa (GET /company).
    def get
      @http.request('Get', '/company')
    end

    # Saldo disponível (GET /company/balance).
    def balance
      @http.request('Get', '/company/balance')
    end
  end

  # Conversões BRL/USDT.
  class Conversions < CrudResource
    def initialize(http)
      super(http, '/conversions')
    end

    # Cotação de conversão (POST /conversions/quote).
    def quote(payload)
      @http.request('Post', '/conversions/quote', body: payload)
    end
  end

  # Infrações / MED.
  class Chargebacks
    def initialize(http)
      @http = http
    end

    def list(query = {})
      path = '/chargebacks'
      unless query.nil? || query.empty?
        path = "#{path}?#{URI.encode_www_form(query)}"
      end
      @http.request('Get', path)
    end

    def get(id)
      @http.request('Get', "/chargebacks/#{URI.encode_www_form_component(id)}")
    end
  end

  # Facade principal da API AurePay.
  class Client
    attr_reader :deposits, :withdrawals, :webhooks, :company, :conversions, :chargebacks, :wallets

    def initialize(api_key:, api_secret:, base_url: 'https://api.aurepay.com.br/v1', max_retries: 2)
      api_key = api_key.to_s.strip
      api_secret = api_secret.to_s.strip
      raise Error.new('api_key and api_secret are required.') if api_key.empty? || api_secret.empty?

      http = HttpTransport.new(
        api_key: api_key,
        api_secret: api_secret,
        base_url: base_url,
        max_retries: max_retries
      )

      @deposits = CrudResource.new(http, '/deposits')
      @withdrawals = CrudResource.new(http, '/withdrawals')
      @webhooks = CrudResource.new(http, '/webhooks')
      @company = Company.new(http)
      @conversions = Conversions.new(http)
      @chargebacks = Chargebacks.new(http)
      @wallets = CrudResource.new(http, '/wallets')
    end
  end

  # Alias ergonômico: AurePay.new(...)
  def self.new(**kwargs)
    Client.new(**kwargs)
  end
end
