<script>
  import { CLIENTS } from '$lib/connect';
</script>

<svelte:head>
  <title>Connect TouchTips to your AI</title>
  <meta name="description" content="Give Claude, ChatGPT, Claude Code, Cursor or any agent a private URL to your TouchTips meetings." />
  <link rel="canonical" href="https://touchtips.app/connect" />
</svelte:head>

<h1 class="serif">Connect</h1>
<p class="lede">Open TouchTips on your iPhone, tap Connect, pick a client. It gives you a URL that is the whole connection. Pick your client below for the steps after that.</p>
<ul class="clients">
  {#each CLIENTS as client}
    <li><a href={`/connect/${client.id}`}><span class="name">{client.name}</span><span class="tagline">{client.tagline}</span></a></li>
  {/each}
</ul>
<div class="note">Don't have the app yet? <a href="/ios">Get TouchTips</a>, then come back.</div>
