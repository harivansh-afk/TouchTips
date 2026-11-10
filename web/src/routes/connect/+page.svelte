<svelte:head>
  <title>Connect TouchTips to Claude or ChatGPT</title>
  <meta name="description" content="Let your AI assistant answer when and where you met someone, straight from TouchTips." />
  <link rel="canonical" href="https://touchtips.app/connect" />
</svelte:head>

<h1>Connect to your AI</h1>
<p>Ask Claude or ChatGPT "when did I meet Sam?" and get the date, the place and a link back to TouchTips. Your phone approves each connection; nothing is shared until you say so.</p>

<h2>Your connector URL</h2>
<p class="url"><code id="mcp-url">https://touchtips.app/mcp</code> <button type="button" id="copy-url">Copy</button></p>

<h2>Claude</h2>
<ol>
  <li>Open Claude settings, then Connectors, then Add custom connector.</li>
  <li>Paste the URL above and tap Connect.</li>
  <li>Claude opens a page with a six-digit code. Tap Open TouchTips, or type the code into TouchTips under Settings, Connected apps.</li>
  <li>Tap Allow. Claude is connected.</li>
</ol>

<h2>ChatGPT</h2>
<ol>
  <li>Open ChatGPT settings, then Apps &amp; Connectors, then Advanced, and turn on Developer mode.</li>
  <li>Create a connector with the URL above and OAuth authentication.</li>
  <li>Approve the code in TouchTips, as with Claude.</li>
</ol>

<h2>Claude Code</h2>
<pre><code>claude mcp add --transport http touchtips https://touchtips.app/mcp</code></pre>
<p>Then run <code>/mcp</code> inside Claude Code to sign in and approve the code in TouchTips.</p>

<h2>What leaves your phone</h2>
<p>Only what TouchTips shows: names, meeting dates, places and your notes. No phone numbers or emails. You can disconnect any app, or delete everything from the cloud, in TouchTips under Settings, Connected apps.</p>

{@html `<script>
  const b = document.getElementById('copy-url');
  b.addEventListener('click', async () => {
    await navigator.clipboard.writeText(document.getElementById('mcp-url').textContent);
    b.textContent = 'Copied';
    setTimeout(() => (b.textContent = 'Copy'), 1500);
  });
</script>`}

<style>
  .url { display: flex; gap: 0.75rem; align-items: center; flex-wrap: wrap; }
  .url code { font-size: 1rem; padding: 0.4rem 0.6rem; border-radius: 0.5rem; background: color-mix(in srgb, currentColor 8%, transparent); }
  .url button { font: inherit; padding: 0.4rem 0.9rem; border-radius: 0.5rem; border: 1px solid currentColor; background: transparent; color: inherit; cursor: pointer; }
  ol { padding-left: 1.25rem; }
  li { margin-bottom: 0.35rem; }
  pre { overflow-x: auto; padding: 0.75rem 1rem; border-radius: 0.5rem; background: color-mix(in srgb, currentColor 8%, transparent); }
</style>
