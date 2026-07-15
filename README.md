# aurepay

SDK oficial da API AurePay para Ruby.

## Instalação

```bash
gem install aurepay
```

## Uso

```ruby
require 'aurepay'

aure = AurePay.new(
  api_key: ENV['AUREPAY_API_KEY'],
  api_secret: ENV['AUREPAY_API_SECRET']
)

aure.deposits.create({ amount: 10_000, method: 'pix' })
aure.webhooks.list
aure.company.balance
```

Docs: https://api.aurepay.com.br/docs/sdks  
OpenAPI: https://api.aurepay.com.br/openapi.yaml
