<script>
  import { page } from '$app/state';
  import '../styles.css';

  let { children } = $props();
</script>

<div class="page">
  <header>
    <a class="brand" href="/support" aria-label="TouchTips support">
      <img src="/icon.png" alt="TouchTips" width="56" height="56" />
    </a>
    <nav aria-label="Information">
      <a href="/support" aria-current={page.url.pathname === '/support' ? 'page' : undefined}>Support</a>
      <a href="/privacy" aria-current={page.url.pathname === '/privacy' ? 'page' : undefined}>Privacy</a>
    </nav>
  </header>
  <main>
    {@render children()}
    <footer>Harivansh Rathi · TouchTips</footer>
  </main>
</div>
