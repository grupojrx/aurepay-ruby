/**
 * Decide se aurepay (RubyGems) deve publicar.
 * exit 0 = publish, 10 = skip, 1 = erro (mudou sem bump)
 */
import { createHash } from 'node:crypto'
import {
  existsSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  statSync,
  writeFileSync
} from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join, relative } from 'node:path'
import { fileURLToPath } from 'node:url'
import { execSync } from 'node:child_process'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const gemName = 'aurepay'
const userAgent = 'AurePaySDKPublish (mailto=dev@aurepay.com.br)'

function walkFiles(dir, files = []) {
  for (const name of readdirSync(dir)) {
    const path = join(dir, name)

    if (statSync(path).isDirectory()) {
      walkFiles(path, files)
    } else {
      files.push(path)
    }
  }

  return files
}

function readLocalVersion() {
  const versionRb = readFileSync(join(root, 'lib/aurepay/version.rb'), 'utf8')
  const match = versionRb.match(/VERSION\s*=\s*['"]([^'"]+)['"]/)

  if (!match) {
    throw new Error('VERSION missing in lib/aurepay/version.rb')
  }

  return match[1]
}

function contentHash(base) {
  const hash = createHash('sha256')
  const gemspecPath = join(base, 'aurepay.gemspec')

  if (existsSync(gemspecPath)) {
    const text = readFileSync(gemspecPath, 'utf8').replaceAll('\r\n', '\n')
    hash.update('aurepay.gemspec\0')
    hash.update(text)
    hash.update('\0')
  }

  const libDir = join(base, 'lib')

  if (!existsSync(libDir)) {
    throw new Error(`lib/ missing in ${base}`)
  }

  const files = walkFiles(libDir).sort((a, b) =>
    relative(base, a).localeCompare(relative(base, b))
  )

  for (const file of files) {
    const rel = relative(base, file).replaceAll('\\', '/')
    // Ignora VERSION no hash de conteúdo (comparado à parte)
    if (rel === 'lib/aurepay/version.rb') {
      const body = readFileSync(file, 'utf8')
        .replaceAll('\r\n', '\n')
        .replace(/VERSION\s*=\s*['"][^'"]+['"]/, "VERSION = '0.0.0'")
      hash.update(rel)
      hash.update('\0')
      hash.update(body)
      hash.update('\0')
      continue
    }

    hash.update(rel)
    hash.update('\0')
    hash.update(readFileSync(file, 'utf8').replaceAll('\r\n', '\n'))
    hash.update('\0')
  }

  return hash.digest('hex')
}

async function fetchRubygems() {
  const response = await fetch(`https://rubygems.org/api/v1/gems/${gemName}.json`, {
    headers: { 'User-Agent': userAgent }
  })

  if (response.status === 404) {
    return null
  }

  if (!response.ok) {
    throw new Error(`RubyGems HTTP ${response.status}`)
  }

  return response.json()
}

const version = readLocalVersion()
const localHash = contentHash(root)
const remote = await fetchRubygems()

if (!remote) {
  console.log(`no remote gem — publish ${gemName}-${version}`)
  process.exit(0)
}

const remoteVersion = String(remote.version || '')

if (remoteVersion === version) {
  // Mesma versão no registry: só publica se o conteúdo mudou (exige bump)
  const gemUrl = `https://rubygems.org/gems/${gemName}-${remoteVersion}.gem`
  const work = mkdtempSync(join(tmpdir(), 'aurepay-ruby-cmp-'))

  try {
    const response = await fetch(gemUrl, {
      headers: { 'User-Agent': userAgent },
      redirect: 'follow'
    })

    if (!response.ok) {
      console.log(`${gemName}-${version} already on RubyGems (no gem to compare) — skip`)
      process.exit(10)
    }

    const gemPath = join(work, 'pkg.gem')
    writeFileSync(gemPath, Buffer.from(await response.arrayBuffer()))

    // .gem é tar; extrai data.tar.gz interno
    execSync(`tar -xf "${gemPath}" -C "${work}"`, { stdio: 'pipe' })
    const dataTar = join(work, 'data.tar.gz')

    if (existsSync(dataTar)) {
      execSync(`tar -xzf "${dataTar}" -C "${work}"`, { stdio: 'pipe' })
    }

    const remoteHash = contentHash(work)

    if (localHash === remoteHash) {
      console.log(
        `SDK unchanged vs ${gemName}-${remoteVersion} — skip (${localHash.slice(0, 12)})`
      )
      process.exit(10)
    }

    console.error(
      `SDK changed, but ${gemName}-${version} already on RubyGems. Bump lib/aurepay/version.rb.`
    )
    process.exit(1)
  } finally {
    rmSync(work, { recursive: true, force: true })
  }
}

console.log(`${gemName}-${version} not on RubyGems (latest ${remoteVersion}) — publish`)
process.exit(0)
