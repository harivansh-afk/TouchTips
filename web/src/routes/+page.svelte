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
  <h1 aria-label="Who was that guy I met in New York?">
    <span aria-hidden="true">Who was that guy I met in <span class="cities" id="cities">{#each cities as city, i}<span class="city" class:on={i === 0}>{#each [...city, '?'] as ch, j}<span style="--j:{j}">{ch === ' ' ? '\u00a0' : ch}</span>{/each}</span>{/each}</span></span>
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
    const els = Array.from(document.querySelectorAll('#cities .city'));
    let i = 0;
    setInterval(() => {
      const prev = els[i];
      prev.classList.replace('on', 'out');
      setTimeout(() => prev.classList.remove('out'), 700);
      i = (i + 1) % els.length;
      els[i].classList.add('on');
    }, 2800);
  })();
</script>`}
