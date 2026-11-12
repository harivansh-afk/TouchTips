<script>
  import { CLIENTS } from '$lib/connect';
  import { CLIENT_ICONS, iconClass, iconStyle } from '$lib/agents';
</script>

<svelte:head>
  <title>TouchTips</title>
  <meta name="description" content="Give Claude, ChatGPT, Grok Bot, Instinct or any agent a private URL to your TouchTips meetings." />
  <link rel="canonical" href="https://touchtips.app/connect" />
</svelte:head>

<div class="connect-head">
  <h1>One URL. Any agent.</h1>
</div>

<ul class="rows">
  {#each CLIENTS as client}
    <li>
      <a href={`/connect/${client.id}`}>
        <span class={iconClass(CLIENT_ICONS[client.id])} style={iconStyle(CLIENT_ICONS[client.id])}></span>
        <span class="name serif">{client.name}</span>
        <span class="arrow" aria-hidden="true">→</span>
      </a>
    </li>
  {/each}
</ul>
