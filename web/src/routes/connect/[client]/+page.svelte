<script>
  let { data } = $props();
  const client = $derived(data.client);
</script>

<svelte:head>
  <title>Connect {client.name} to TouchTips</title>
  <meta name="description" content={`Connect ${client.name} to your TouchTips meetings.`} />
  <link rel="canonical" href={`https://touchtips.app/connect/${client.id}`} />
</svelte:head>

<p class="eyebrow"><img src={`/icons/${client.id}.svg`} alt="" width="22" height="22" /></p>
<h1 class="serif">Connect {client.name}</h1>
<p class="lede">In TouchTips, tap the plug, then <strong class="muted">{client.name}</strong>. The URL is on your clipboard.</p>
<ol class="steps">
  {#each client.steps as step}
    <li>{step}</li>
  {/each}
</ol>
<div class="actions">
  <a class="button primary" href="/ios">Get TouchTips</a>
</div>
