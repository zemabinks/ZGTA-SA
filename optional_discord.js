// Optional Discord identity linking. The client secret and tokens never enter
// the browser bundle, player save file, or source repository.
const crypto = require('node:crypto');

class OptionalDiscord {
  constructor(config = {}, fetcher = globalThis.fetch) {
    const {clientId, clientSecret, redirectUri} = config;
    this.enabled = !!(clientId && clientSecret && redirectUri);
    if (Object.keys(config).length && !this.enabled)
      throw new Error('Discord OAuth config needs clientId, clientSecret, and redirectUri.');
    if (this.enabled) {
      const redirect = new URL(redirectUri);
      if (!/^\d{17,22}$/.test(clientId) || redirect.pathname !== '/api/local/discord/callback' ||
          redirect.search || redirect.hash || redirect.username || redirect.password ||
          (redirect.protocol !== 'https:' &&
            !(redirect.protocol === 'http:' && ['127.0.0.1', 'localhost'].includes(redirect.hostname))))
        throw new Error('Discord OAuth config has an invalid clientId or redirectUri.');
      this.clientId = clientId;
      this.clientSecret = clientSecret;
      this.redirectUri = redirectUri;
      this.redirectHost = redirect.host;
    }
    this.fetcher = fetcher;
    this.pending = new Map();
  }

  start(playerId) {
    if (!this.enabled) throw new Error('Discord linking is not configured.');
    for (const [state, item] of this.pending) if (item.expires < Date.now()) this.pending.delete(state);
    if (this.pending.size >= 1024) throw new Error('Too many pending Discord sign-ins. Try again shortly.');
    const state = crypto.randomBytes(24).toString('hex');
    const verifier = crypto.randomBytes(32).toString('base64url');
    const challenge = crypto.createHash('sha256').update(verifier).digest('base64url');
    this.pending.set(state, {playerId, verifier, expires: Date.now() + 10 * 60 * 1000});
    const url = new URL('https://discord.com/oauth2/authorize');
    url.search = new URLSearchParams({response_type: 'code', client_id: this.clientId,
      scope: 'identify', state, redirect_uri: this.redirectUri,
      code_challenge: challenge, code_challenge_method: 'S256'}).toString();
    return url.toString();
  }

  async finish({state, code, iss, playerId}) {
    if (!this.enabled) throw new Error('Discord linking is not configured.');
    const request = this.pending.get(state);
    this.pending.delete(state);
    if (!request || request.expires < Date.now() || request.playerId !== playerId ||
        iss !== 'https://discord.com' || typeof code !== 'string' ||
        !code || code.length > 2048)
      throw new Error('Discord sign-in expired or failed validation. Please try again.');
    const tokenResponse = await this.fetcher('https://discord.com/api/oauth2/token', {
      method: 'POST', headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: new URLSearchParams({grant_type: 'authorization_code', code,
        redirect_uri: this.redirectUri, client_id: this.clientId,
        client_secret: this.clientSecret, code_verifier: request.verifier}),
      signal: AbortSignal.timeout(10000),
    });
    if (!tokenResponse.ok) throw new Error('Discord did not accept the sign-in code.');
    const token = await tokenResponse.json();
    if (token.token_type !== 'Bearer' || typeof token.access_token !== 'string' ||
        !token.access_token || !String(token.scope || '').split(' ').includes('identify'))
      throw new Error('Discord did not return an identify token.');
    const userResponse = await this.fetcher('https://discord.com/api/v10/users/@me', {
      headers: {Authorization: `Bearer ${token.access_token}`},
      signal: AbortSignal.timeout(10000),
    });
    if (!userResponse.ok) throw new Error('Discord could not identify this account.');
    const user = await userResponse.json();
    if (!/^\d{17,22}$/.test(String(user.id || '')))
      throw new Error('Discord returned an invalid account ID.');
    return {id: user.id, name: String(user.global_name || user.username || 'Discord player').slice(0, 80)};
  }
}

module.exports = OptionalDiscord;
