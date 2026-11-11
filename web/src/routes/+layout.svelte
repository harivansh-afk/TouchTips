<script>
  import { page } from '$app/state';
  import '../styles.css';

  let { children } = $props();
  const current = (path) => (page.url.pathname === path || page.url.pathname.startsWith(path + '/') ? 'page' : undefined);
</script>

<div class="page">
  <div class="top">
    <a class="wordmark serif" href="/" aria-label="TouchTips home">TouchTips</a>
    <nav aria-label="Site">
      <a href="/connect" aria-current={current('/connect')}>Connect</a>
      <a href="/ios">Get the app</a>
    </nav>
  </div>
  <main>
    {@render children()}
  </main>
  <footer>
    <span>© {new Date().getFullYear()} TouchTips</span>
    <a href="/support">Support</a>
    <a href="/privacy">Privacy</a>
    <a href="https://github.com/harivansh-afk/TouchTips">Source</a>
  </footer>
</div>
