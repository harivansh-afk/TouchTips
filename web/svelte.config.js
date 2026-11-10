import adapter from '@sveltejs/adapter-vercel';

export default {
  kit: {
    adapter: adapter({ runtime: 'nodejs24.x' }),
    paths: { relative: false },
  },
};
