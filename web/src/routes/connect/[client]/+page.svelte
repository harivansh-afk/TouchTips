<script>
  import { CLIENT_ICONS, iconClass, iconStyle } from '$lib/agents';
  import { claudeCodeCommand } from '$lib/connect';
  let { data } = $props();
  const client = $derived(data.client);
</script>

<svelte:head>
  <title>TouchTips</title>
  <meta name="description" content={`Connect ${client.name} to your TouchTips meetings.`} />
  <link rel="canonical" href={`https://touchtips.app/connect/${client.id}`} />
</svelte:head>

<p class="eyebrow"><span class={iconClass(CLIENT_ICONS[client.id])} style={iconStyle(CLIENT_ICONS[client.id])}></span></p>
<h1>Connect {client.name}</h1>
<p class="lede">In TouchTips, tap the plug, then <strong class="muted">{client.name}</strong>, then Open {client.name}.{#if client.where}{" "}On a computer: {client.where}.{/if}</p>
<ol class="steps">
  {#each client.steps as step}
    <li>{step}</li>
  {/each}
</ol>
{#if client.id === 'claude'}
  <h2>Claude Code</h2>
  <p>The app has the same URL as a command. Run it, then <code>/mcp</code> in Claude Code to sign in.</p>
  <pre>{claudeCodeCommand('https://touchtips.app/u/…/mcp')}</pre>
{/if}
<div class="actions">
  <a class="button primary" href="/ios">Get TouchTips</a>
</div>
