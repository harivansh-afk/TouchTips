<script>
  import { AGENTS, iconClass, iconStyle } from '$lib/agents';
</script>

<svelte:head>
  <title>TouchTips — remember everyone you meet</title>
  <meta name="description" content="TouchTips is the iPhone app that remembers everyone you meet. Claude, ChatGPT and any agent can ask it." />
  <link rel="canonical" href="https://touchtips.app/" />
</svelte:head>

<div class="hero">
  <h1 class="serif">Who was that guy I met in <span class="city" id="city">New York</span>?</h1>
  <p class="lede">The app that remembers everyone.</p>
  <a class="button ios" href="/ios"><span class="ico" style="--i:url(/agents/apple.svg)"></span>Download for iOS</a>
</div>

<ul class="agents">
  {#each AGENTS as agent}
    <li><a href={`/connect/${agent.client}`}><span class={iconClass(agent.icon)} style={iconStyle(agent.icon)}></span>{agent.name}</a></li>
  {/each}
</ul>

{@html `<script>
  (() => {
    const el = document.getElementById('city');
    if (!el || matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    const cities = ['New York', 'Lisbon', 'Tokyo', 'Berlin', 'Austin', 'London', 'Paris', 'Mumbai', 'Toronto', 'Sydney'];
    let i = 0;
    setInterval(() => {
      el.classList.add('out');
      setTimeout(() => {
        i = (i + 1) % cities.length;
        el.textContent = cities[i];
        el.classList.remove('out');
      }, 260);
    }, 2600);
  })();
</script>`}
