const repository = 'Xanerix/guoapp';
const platforms = new Set(['android', 'ios', 'windows', 'darwin', 'linux']);
const builds = new Set(['hongguojian', 'zhenguojian']);

const json = (body, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });

const beijingDay = () =>
  new Date(Date.now() + 8 * 3600 * 1000).toISOString().slice(0, 10);

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === 'GET' && url.pathname === '/v1/latest') {
      const latest = await env.DB.prepare(
        "SELECT value FROM meta WHERE key = 'latest'",
      ).first('value');
      return json(latest ? JSON.parse(latest) : {});
    }
    if (request.method !== 'POST' || url.pathname !== '/v1/ping') {
      return new Response('Not Found', { status: 404 });
    }
    let body;
    try {
      body = await request.json();
    } catch {
      return json({ error: 'invalid' }, 400);
    }
    const { id, version, platform, build } = body ?? {};
    if (
      !/^[0-9a-f]{32}$/.test(id) ||
      !/^\d+\.\d+\.\d+\+\d+$/.test(version) ||
      !platforms.has(platform) ||
      !builds.has(build)
    ) {
      return json({ error: 'invalid' }, 400);
    }
    await env.DB.prepare(
      `INSERT INTO pings (day, id, version, platform, build) VALUES (?1, ?2, ?3, ?4, ?5)
       ON CONFLICT (day, id) DO UPDATE SET version = excluded.version, platform = excluded.platform, build = excluded.build`,
    )
      .bind(beijingDay(), id, version, platform, build)
      .run();
    return new Response(null, { status: 204 });
  },

  async scheduled(_, env) {
    const response = await fetch(
      `https://api.github.com/repos/${repository}/releases/latest`,
      {
        headers: {
          Accept: 'application/vnd.github+json',
          'User-Agent': 'guoapp-update',
        },
      },
    );
    if (!response.ok) return;
    const release = await response.json();
    const match = /^app-v(\d+\.\d+\.\d+)-(\d+)$/.exec(release.tag_name ?? '');
    if (!match) return;
    const latest = { version: `${match[1]}+${match[2]}`, url: release.html_url };
    await env.DB.prepare(
      "INSERT INTO meta (key, value) VALUES ('latest', ?1) ON CONFLICT (key) DO UPDATE SET value = excluded.value",
    )
      .bind(JSON.stringify(latest))
      .run();
  },
};
