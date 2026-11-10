<script lang="ts">
  import Icon from '../components/Icon.svelte';
</script>

<div class="page-head">
  <div><p class="page-kicker">Coming later</p><h1>Marketplace</h1><p>A place for members to buy and sell locally. It is not connected to the ledger yet.</p></div>
</div>

<section class="market-hero">
  <div><span class="status-pill on-purple"><i></i>Planned</span><h2>Buy and sell within your chama.</h2><p>Phones, household goods, farm produce and services from people you already trust. Checkout, escrow and delivery are not built in this phase.</p></div>
  <div class="market-art"><Icon name="marketplace" size={64} /></div>
</section>

<div class="market-categories">
  <div class="market-category"><span class="kpi-icon purple"><Icon name="marketplace" size={20} /></span><strong>Phones</strong><small>Devices and accessories</small></div>
  <div class="market-category"><span class="kpi-icon green"><Icon name="chamas" size={20} /></span><strong>Home</strong><small>Furniture and living</small></div>
  <div class="market-category"><span class="kpi-icon amber"><Icon name="transactions" size={20} /></span><strong>Farm produce</strong><small>Direct from members</small></div>
  <div class="market-category"><span class="kpi-icon pink"><Icon name="profile" size={20} /></span><strong>Services</strong><small>Skills and errands</small></div>
</div>

<section class="empty-state-card">
  <span class="empty-icon"><Icon name="marketplace" size={28} /></span>
  <h2>Not open for trading</h2>
  <p>The marketplace needs its own listings, orders and dispute rules. Nothing here can move money or create an escrow obligation.</p>
</section>
