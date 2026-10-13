const canonical = 'pingwarden.app';
const hosts = new Set([canonical, `www.${canonical}`]);
// Older links and shares used /dashboard.png before the version 4 capture.
const moved = new Map([['/dashboard.png', '/dashboard-v4.png']]);

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    // Only production hosts are redirected so `wrangler dev` keeps working over http://localhost.
    if (hosts.has(url.hostname) && (url.protocol === 'http:' || url.hostname !== canonical || moved.has(url.pathname))) {
      url.protocol = 'https:';
      url.hostname = canonical;
      url.pathname = moved.get(url.pathname) ?? url.pathname;
      return Response.redirect(url.href, 301);
    }
    return env.ASSETS.fetch(request);
  }
};
