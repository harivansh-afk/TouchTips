<svelte:head>
  <title>TouchTips</title>
  <meta name="description" content="How TouchTips handles your data." />
  <link rel="canonical" href="https://touchtips.app/privacy" />
</svelte:head>

<h1>Privacy</h1>
<p class="date">Effective November 11, 2026</p>
<p>TouchTips is developed by <a href="https://harivan.sh">Harivansh Rathi</a>. It stores meeting details and notes on your iPhone. No account is required.</p>

<h2>Contacts</h2>
<p>With your permission, the app reads your contacts to notice new ones. Unless you connect an AI app (below), nothing leaves your iPhone: your contacts, meeting history and notes are not sent to the developer. There are no ads, analytics or tracking.</p>

<h2>Connecting an AI app</h2>
<p>If you choose to connect an AI app such as Claude or ChatGPT, TouchTips keeps a copy on its server (touchtips.app) so that app can read it: the names of people in TouchTips, when and where you met them (place names and coordinates), and your notes. Phone numbers, emails and the rest of your contacts are not sent. It is stored encrypted, and only a request from your iPhone or from an app you allowed can unlock it. It stays current while any app is connected.</p>
<p>An app can read it only after you tap Allow in TouchTips, and only to answer you; it cannot change anything. What it does with what it reads is covered by that app's own privacy policy. The server runs on Vercel, with its database at Neon.</p>
<p>Disconnect any app in TouchTips under Connect. “Delete cloud data” there removes the copy and every connection at once.</p>

<h2>Location</h2>
<p>With your permission, and only while TouchTips is open, the app reads your location to suggest where you met someone: when you add a person in the app, and when you open it within 20 minutes of saving a new contact. It never reads your location in the background. Only the named place is saved with the meeting, on your iPhone; your location is not tracked or kept as a history. You can turn location off in iPhone Settings and choose places by search instead.</p>

<h2>Apple services</h2>
<p>Maps and place searches use Apple services and may send requests to Apple. They are covered by <a href="https://www.apple.com/legal/privacy/">Apple’s privacy policy</a>. Contact syncing and device backups follow your iPhone settings.</p>

<h2>Control and deletion</h2>
<p>Change permissions in iPhone Settings. You can edit or remove individual records in TouchTips, or choose “Delete all data” to clear them, along with any copy on the server and every connected app. This does not delete your iPhone contacts.</p>

<h2>Contact</h2>
<p>For privacy questions, email <a href="mailto:hari@touchtips.app">hari@touchtips.app</a>. Your email address and message are used to respond.</p>
