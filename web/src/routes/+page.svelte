<script>
  import { AGENTS, iconClass, iconStyle } from '$lib/agents';
</script>

<svelte:head>
  <title>TouchTips — never forget anyone again</title>
  <meta name="description" content="TouchTips is the iPhone app that remembers everyone you meet. Claude, ChatGPT and any agent can ask it." />
  <link rel="canonical" href="https://touchtips.app/" />
</svelte:head>

<div class="hero">
  <h1>Never forget anyone again.</h1>
  <figure class="demo" id="demo" data-muted data-paused>
    <video src="/launch.mp4" poster="/launch.jpg" muted loop playsinline preload="auto" aria-label="TouchTips demo: tap phones, then ask any agent who you met"></video>
    <div class="controls">
      <button type="button" data-act="play" aria-label="Play or pause">
        <svg class="when-paused" viewBox="0 0 24 24" aria-hidden="true"><path d="M8 5.5v13l11-6.5z" fill="currentColor"/></svg>
        <svg class="when-playing" viewBox="0 0 24 24" aria-hidden="true"><path d="M7 5h3.5v14H7zM13.5 5H17v14h-3.5z" fill="currentColor"/></svg>
      </button>
      <button type="button" data-act="sound" aria-label="Sound on or off">
        <svg class="when-muted" viewBox="0 0 24 24" aria-hidden="true"><path d="M4 9.5h3.5L12 5.5v13l-4.5-4H4z" fill="currentColor"/><path d="M16 9.5l5 5M21 9.5l-5 5" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" fill="none"/></svg>
        <svg class="when-sound" viewBox="0 0 24 24" aria-hidden="true"><path d="M4 9.5h3.5L12 5.5v13l-4.5-4H4z" fill="currentColor"/><path d="M15.5 9a4.2 4.2 0 0 1 0 6M18.2 6.5a8 8 0 0 1 0 11" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" fill="none"/></svg>
      </button>
    </div>
  </figure>
  <a class="button primary lg" href="/ios"><span class="ico" style="--i:url(/agents/apple.svg)"></span>Download for iOS</a>
</div>

<ul class="agents">
  {#each AGENTS as agent}
    <li><a href={`/connect/${agent.client}`}><span class={iconClass(agent.icon)} style={iconStyle(agent.icon)}></span>{agent.name}</a></li>
  {/each}
</ul>

{@html `<script>
  (() => {
    const fig = document.getElementById('demo');
    const v = fig.querySelector('video');
    const sync = () => { fig.toggleAttribute('data-paused', v.paused); fig.toggleAttribute('data-muted', v.muted); };
    ['play', 'pause', 'volumechange'].forEach((e) => v.addEventListener(e, sync));
    const toggle = () => (v.paused ? v.play() : v.pause());
    v.addEventListener('click', toggle);
    fig.querySelector('[data-act=play]').addEventListener('click', toggle);
    fig.querySelector('[data-act=sound]').addEventListener('click', () => { v.muted = !v.muted; if (!v.muted && v.paused) v.play(); });
    // Try with sound; browsers that block unmuted autoplay get it muted, one tap from sound.
    v.muted = false;
    v.play().catch(() => { v.muted = true; return v.play(); }).catch(() => {}).finally(sync);
  })();
</script>`}
