<script>
  import { CLIENTS } from '$lib/connect';
</script>

<svelte:head>
  <title>TouchTips — ask your AI when you met someone</title>
  <meta name="description" content="TouchTips remembers when and where you met each contact. Claude, ChatGPT, Instinct, Grok and any agent can read it back to you." />
  <link rel="canonical" href="https://touchtips.app/" />
</svelte:head>

<h1 class="serif">Ask your AI when you met someone.</h1>
<p class="lede">TouchTips notices every new contact on your iPhone and remembers the day and the place. Connect it once, and your AI can answer “when did I meet Sam?” with the date, the place, and a link back to them.</p>
<div class="actions">
  <a class="button primary" href="/ios">Get the app</a>
</div>

<figure class="demo">
  <video controls muted playsinline preload="none" poster="/demo-poster.jpg" width="1280" height="720" aria-label="TouchTips demo" aria-describedby="demo-caption">
    <source src="/demo.mp4" type="video/mp4" />
    <a href="/demo.mp4">Watch the TouchTips demo</a>.
  </video>
  <figcaption id="demo-caption">22 seconds of TouchTips</figcaption>
</figure>

<h2 class="serif" id="connect">One tap in the app.</h2>
<ul class="clients">
  {#each CLIENTS as client}
    <li><a href={`/connect/${client.id}`}><img src={`/icons/${client.id}.svg`} alt="" width="22" height="22" /><span class="name">{client.name}</span></a></li>
  {/each}
</ul>

<h2 class="serif">What leaves your phone</h2>
<p>Names, meeting dates, places and your notes. No phone numbers, no emails, no contacts upload. Each client gets its own URL; disconnect one with a tap, or delete the cloud copy entirely.</p>
