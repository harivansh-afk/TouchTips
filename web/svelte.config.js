import adapter from '@sveltejs/adapter-vercel';

export default {
  kit: {
    adapter: adapter({ runtime: 'nodejs24.x' }),
    paths: { relative: false },
    // OAuth clients post form-encoded token requests with no Origin header. Nothing here is a
    // cookie-authenticated form, so SvelteKit's cross-site check only gets in the way.
    csrf: { checkOrigin: false },
  },
};
