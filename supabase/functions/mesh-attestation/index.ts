import { createClient } from 'npm:@supabase/supabase-js@2.118.0'
import nacl from 'npm:tweetnacl@1.0.3'

const headers = {
  'Content-Type': 'application/json',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Cache-Control': 'no-store',
}
const reply = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), { status, headers })
const from64 = (value: string) => Uint8Array.from(atob(value), c => c.charCodeAt(0))
const to64 = (value: Uint8Array) => btoa(String.fromCharCode(...value))
const bytes = (value: unknown) => new TextEncoder().encode(JSON.stringify(value))
const admin = createClient(
  Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  { auth: { persistSession: false, autoRefreshToken: false } },
)
let issuer: Promise<{ keyId: string; publicKey: Uint8Array; secretKey: Uint8Array }> | undefined
function getIssuer() {
  return issuer ??= (async () => {
    const { data, error } = await admin.rpc('mesh_issuer_seed')
    if (error || !data?.seed) throw new Error('Issuer unavailable')
    const pair = nacl.sign.keyPair.fromSeed(from64(data.seed))
    return { keyId: data.key_id as string, ...pair }
  })().catch(error => { issuer = undefined; throw error })
}

// GET only publishes the verification key. POST always validates a current
// user with Auth; anonymous/public API keys cannot obtain an attestation.
Deno.serve(async req => {
  if (req.method === 'OPTIONS') return new Response(null, { headers })
  try {
    if (req.method === 'GET') {
      const key = await getIssuer()
      return reply({ keyId: key.keyId, publicKey: to64(key.publicKey), algorithm: 'Ed25519' })
    }
    if (req.method !== 'POST') return reply({ error: 'Method not allowed' }, 405)
    const authorization = req.headers.get('Authorization') ?? ''
    const match = /^Bearer (\S+)$/i.exec(authorization)
    if (!match) return reply({ error: 'Authentication required' }, 401)
    const { data: { user }, error: authError } = await admin.auth.getUser(match[1])
    if (authError || !user || user.is_anonymous) return reply({ error: 'Authentication required' }, 401)
    const text = await req.text()
    if (text.length > 8192) return reply({ error: 'Request too large' }, 413)
    const cert = JSON.parse(text).certificate
    if (!cert || cert.userId !== user.id ||
      typeof cert.device !== 'string' || cert.device.length < 1 || cert.device.length > 128 ||
      typeof cert.name !== 'string' || cert.name.length > 200 ||
      typeof cert.ed !== 'string' || typeof cert.x !== 'string' || typeof cert.signature !== 'string') {
      return reply({ error: 'Invalid device certificate' }, 400)
    }
    const ed = from64(cert.ed), x = from64(cert.x), signature = from64(cert.signature)
    if (ed.length !== 32 || x.length !== 32 || signature.length !== 64) {
      return reply({ error: 'Invalid key' }, 400)
    }
    const canonical = Object.fromEntries(Object.entries(cert)
      .filter(([k]) => k !== 'signature').sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0))
    if (!nacl.sign.detached.verify(bytes(canonical), signature, ed)) {
      return reply({ error: 'Device possession proof rejected' }, 403)
    }
    const jwtPayload = match[1].split('.')[1]
    const claims = JSON.parse(new TextDecoder().decode(from64(
      jwtPayload.replace(/-/g, '+').replace(/_/g, '/'))))
    if (typeof claims.session_id !== 'string') return reply({ error: 'Session required' }, 401)
    const { data: role, error: roleError } = await admin.rpc('mesh_attestation_role',
      { p_user: user.id, p_session: claims.session_id })
    if (roleError || !role) return reply({ error: 'Role unavailable' }, 503)
    const now = Math.floor(Date.now() / 1000)
    const payload = bytes({
      v: 1, iss: 'evfopzvqsngrunopxgvl', sub: user.id,
      device: cert.device, ed: cert.ed, x: cert.x,
      role, iat: now, exp: now + 30 * 86400,
    })
    const key = await getIssuer()
    return reply({
      keyId: key.keyId, payload: to64(payload),
      signature: to64(nacl.sign.detached(payload, key.secretKey)),
    })
  } catch {
    // Never return tokens, issuer material, SQL errors, or request contents.
    return reply({ error: 'Attestation unavailable' }, 503)
  }
})
