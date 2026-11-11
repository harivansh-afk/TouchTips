<script>
  import { AGENTS, iconClass, iconStyle } from '$lib/agents';
  const cities = ['New York', 'Lisbon', 'Tokyo', 'Berlin', 'Austin', 'London', 'Paris', 'Mumbai', 'Sydney', 'Chicago'];
</script>

<svelte:head>
  <title>TouchTips — remember everyone you meet</title>
  <meta name="description" content="TouchTips is the iPhone app that remembers everyone you meet. Claude, ChatGPT and any agent can ask it." />
  <link rel="canonical" href="https://touchtips.app/" />
</svelte:head>

<div class="hero">
  <h1 class="lines" id="lines" aria-label="Who was that guy I met in New York?">
    {#each cities as city, i}
      <span class="line" class:on={i === 0} aria-hidden={i !== 0}>Who was that guy I met in {city}?</span>
    {/each}
  </h1>
  <p class="lede">The app that remembers everyone.</p>
  <a class="button primary lg" href="/ios"><span class="ico" style="--i:url(/agents/apple.svg)"></span>Download for iOS</a>
</div>

<ul class="agents">
  {#each AGENTS as agent}
    <li><a href={`/connect/${agent.client}`}><span class={iconClass(agent.icon)} style={iconStyle(agent.icon)}></span>{agent.name}</a></li>
  {/each}
</ul>

{@html `<script>
  (() => {
    if (matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    const lines = Array.from(document.querySelectorAll('#lines .line'));
    let i = 0;
    setInterval(() => {
      const prev = lines[i];
      prev.classList.replace('on', 'out');
      setTimeout(() => prev.classList.remove('out'), 400);
      i = (i + 1) % lines.length;
      lines[i].classList.add('on');
    }, 2800);
  })();
</script>`}
