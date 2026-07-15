# frozen_string_literal: true

require_relative 'lib/aurepay/version'

Gem::Specification.new do |spec|
  spec.name = 'aurepay'
  spec.version = AurePay::VERSION
  spec.authors = ['AurePay']
  spec.email = ['dev@aurepay.com.br']

  spec.summary = 'SDK oficial da API AurePay para Ruby'
  spec.description = 'SDK oficial da API AurePay para Ruby (tipado via OpenAPI)'
  spec.homepage = 'https://api.aurepay.com.br/docs/sdks'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.1.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/grupojrx/aurepay-ruby'
  spec.metadata['documentation_uri'] = 'https://api.aurepay.com.br/docs'

  spec.files = Dir.chdir(__dir__) do
    Dir['lib/**/*', 'LICENSE', 'README.md'].select { |f| File.file?(f) }
  end

  spec.require_paths = ['lib']
end
