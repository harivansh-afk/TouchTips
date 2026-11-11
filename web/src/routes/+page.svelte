<script>
  import { AGENTS, iconClass, iconStyle } from '$lib/agents';
</script>

<svelte:head>
  <title>TouchTips — remember everyone you meet</title>
  <meta name="description" content="TouchTips is the iPhone app that remembers everyone you meet. Claude, ChatGPT and any agent can ask it." />
  <link rel="canonical" href="https://touchtips.app/" />
</svelte:head>

<div class="hero">
  <h1 class="serif">Who was that guy I met in New York?</h1>
  <p class="lede">The iPhone app that remembers everyone you meet. Your AI can ask it.</p>
  <a class="button primary" href="/ios">Get the app</a>
</div>

<ul class="agents">
  {#each AGENTS as agent}
    <li><a href={`/connect/${agent.client}`}><span class={iconClass(agent.icon)} style={iconStyle(agent.icon)}></span>{agent.name}</a></li>
  {/each}
</ul>
