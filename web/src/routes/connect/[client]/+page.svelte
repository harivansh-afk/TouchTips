<script>
  import { CLIENT_ICONS, iconClass, iconStyle } from '$lib/agents';
  import { claudeCodeCommand } from '$lib/connect';
  let { data } = $props();
  const client = $derived(data.client);
</script>

<svelte:head>
  <title>Connect {client.name} to TouchTips</title>
  <meta name="description" content={`Connect ${client.name} to your TouchTips meetings.`} />
  <link rel="canonical" href={`https://touchtips.app/connect/${client.id}`} />
</svelte:head>

<p class="eyebrow"><span class={iconClass(CLIENT_ICONS[client.id])} style={iconStyle(CLIENT_ICONS[client.id])}></span></p>
<h1 class="serif">Connect {client.name}</h1>
<p class="lede">In TouchTips, tap the plug, then <strong class="muted">{client.name}</strong>. The URL is on your clipboard.</p>
<ol class="steps">
  {#each client.steps as step}
    <li>{step}</li>
  {/each}
</ol>
{#if client.id === 'claude'}
  <p class="lede" style="margin-top:28px">Claude Code: the app copies the same URL as a command.</p>
  <pre>{claudeCodeCommand('https://touchtips.app/c/…/mcp')}</pre>
{/if}
<div class="actions">
  <a class="button primary" href="/ios">Get TouchTips</a>
</div>
