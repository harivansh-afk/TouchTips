import adapter from '@sveltejs/adapter-vercel';

export default {
  kit: {
    adapter: adapter({ runtime: 'nodejs24.x' }),
    paths: { relative: false },
    // OAuth clients post form-encoded token requests from other origins. No route here trusts cookies, so the
    // origin check has nothing to protect.
    csrf: { trustedOrigins: ['*'] },
    prerender: {
      // /ios is a Vercel redirect to TestFlight (vercel.json), not a route.
      handleHttpError: ({ path, message }) => {
        if (path === '/ios') return;
        throw new Error(message);
      },
    },
  },
};
