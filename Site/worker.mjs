export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.hostname === 'www.pingwarden.app') {
      url.hostname = 'pingwarden.app';
      url.protocol = 'https:';
      return Response.redirect(url.href, 301);
    }
    return env.ASSETS.fetch(request);
  }
};
