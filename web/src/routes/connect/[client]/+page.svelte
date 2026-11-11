<script>
  import { PLACEHOLDER_URL, claudeCodeCommand } from '$lib/connect';
  let { data } = $props();
  const client = $derived(data.client);
</script>

<svelte:head>
  <title>Connect {client.name} to TouchTips</title>
  <meta name="description" content={`Steps to connect ${client.name} to your TouchTips meetings.`} />
  <link rel="canonical" href={`https://touchtips.app/connect/${client.id}`} />
</svelte:head>

<h1 class="serif">Connect {client.name}</h1>
<p class="lede">In TouchTips on your iPhone: <strong class="muted">Settings → Connect → {client.name}</strong>. The app puts a private URL on your clipboard. Then:</p>

<ol class="steps">
  {#each client.steps as step}
    <li>{step}</li>
  {/each}
</ol>

{#if client.id === 'claude-code'}
  <p class="small">The command the app copies looks like this, with your URL in it:</p>
  <pre>{claudeCodeCommand(PLACEHOLDER_URL)}</pre>
{:else if client.installLink}
  <p class="small">The app also offers a Share button for the install link, so you can AirDrop it to the computer that runs {client.name}.</p>
{/if}

<div class="note">Changed your mind? Swipe the connection away in TouchTips and the URL stops working at once.</div>
