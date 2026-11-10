<script lang="ts">
  import Icon from '../components/Icon.svelte';
  import { session } from '../lib/session.svelte';
  import './landing.css';

  let { signedIn = false }: { signedIn?: boolean } = $props();

  const appHref = '/app#/overview';
  const startHref = $derived(signedIn ? appHref : '/login');
  const startLabel = $derived(signedIn ? 'Open dashboard' : 'Start your chama');
</script>

<div class="mkt">
  <header class="mkt-nav">
    <div class="mkt-wrap mkt-nav-inner">
      <a class="mkt-brand" href="/" aria-label="{session.appName} home">
        <span class="mkt-brand-mark" aria-hidden="true"><i></i><i></i><i></i></span>
        <span class="mkt-brand-copy">
          <strong>{session.appName}</strong>
          <small>Shared chama ledger</small>
        </span>
      </a>

      <nav class="mkt-nav-links" aria-label="About the product">
        <a href="#ledger">Why a ledger</a>
        <a href="#inside">What's inside</a>
        <a href="#how">How it works</a>
        <a href="#committee">For committees</a>
      </nav>

      <div class="mkt-nav-actions">
        {#if signedIn}
          <a class="mkt-nav-signin" href={appHref}>Open dashboard</a>
        {:else}
          <a class="mkt-nav-signin" href="/login">Sign in</a>
          <a class="mkt-button mkt-button-lime mkt-button-small" href={startHref}>
            Start your chama
            <Icon name="arrow" size={15} />
          </a>
        {/if}
      </div>
    </div>
  </header>

  <main>
    <section class="mkt-hero" aria-labelledby="mkt-hero-title">
      <div class="mkt-wrap mkt-hero-grid">
        <div class="mkt-hero-copy">
          <p class="mkt-kicker"><i class="mkt-kicker-dot" aria-hidden="true"></i>For chamas that keep their own money</p>
          <h1 id="mkt-hero-title">The chama remembers.</h1>
          <p class="mkt-lede">
            Contributions, loans, welfare, fines and rotation turns in one shared ledger every member
            can open. Your money still moves on your chama's own M-Pesa shortcode.
          </p>
          <div class="mkt-actions">
            <a class="mkt-button mkt-button-lime" href={startHref}>
              {startLabel}
              <Icon name="arrow" size={17} />
            </a>
            <a class="mkt-button mkt-button-outline" href="#ledger">See how the ledger works</a>
          </div>
          <ul class="mkt-proof" aria-label="What the platform does">
            <li>Every entry has a name</li>
            <li>Committee-controlled approvals</li>
            <li>No money held</li>
          </ul>
        </div>

        <div class="mkt-hero-stage">
          <div class="mkt-sheet">
            <div class="mkt-sheet-head">
              <div>
                <p class="mkt-sheet-label">Sample ledger</p>
                <h2>Umoja Women</h2>
                <p class="mkt-sheet-meta">October 2026 <span></span> 12 members</p>
              </div>
              <span class="mkt-sheet-badge"><i aria-hidden="true"></i>Balanced</span>
            </div>

            <div class="mkt-sheet-balance">
              <span>Closing balance</span>
              <strong>KES 48,500</strong>
              <small>As at 31 October</small>
            </div>

            <div class="mkt-sheet-columns">
              <span>Entry</span>
              <span>Amount</span>
            </div>

            <ul class="mkt-entries" aria-label="Recent ledger entries">
              <li>
                <div class="mkt-entry-person">
                  <span class="mkt-initials">MW</span>
                  <span><strong>M. Wanjiku</strong><small>Contribution <b>M-PESA SLK7</b></small></span>
                </div>
                <span class="mkt-amount mkt-amount-in">+2,000</span>
              </li>
              <li>
                <div class="mkt-entry-person">
                  <span class="mkt-initials">JO</span>
                  <span><strong>J. Otieno</strong><small>Loan repayment</small></span>
                </div>
                <span class="mkt-amount mkt-amount-in">+3,500</span>
              </li>
              <li>
                <div class="mkt-entry-person">
                  <span class="mkt-initials mkt-initials-out">WF</span>
                  <span><strong>Welfare payout</strong><small>Approved by 3 committee members</small></span>
                </div>
                <span class="mkt-amount mkt-amount-out">−5,000</span>
              </li>
              <li>
                <div class="mkt-entry-person">
                  <span class="mkt-initials">FA</span>
                  <span><strong>F. Achieng</strong><small>Late meeting fine</small></span>
                </div>
                <span class="mkt-amount mkt-amount-in">+200</span>
              </li>
            </ul>

            <div class="mkt-sheet-foot">
              <span><i aria-hidden="true"></i>Ready for the AGM</span>
              <span>4 of 12 turns paid</span>
            </div>
          </div>

          <aside class="mkt-payout-note" aria-label="Next rotation turn">
            <span>Next rotation turn</span>
            <strong>A. Mwangi</strong>
            <small>Turn 4 of 12</small>
          </aside>
        </div>
      </div>
    </section>

    <div class="mkt-statement">
      <div class="mkt-wrap mkt-statement-inner">
        <p>Built for the way chamas actually meet: monthly, in person, with a treasurer and a record everyone can check.</p>
        <a href="#inside">See what's inside <Icon name="arrow" size={16} /></a>
      </div>
    </div>

    <section class="mkt-section mkt-why" id="ledger">
      <div class="mkt-wrap">
        <div class="mkt-section-head">
          <div>
            <p class="mkt-kicker">Why a ledger</p>
            <h2>A chama runs on trust. Trust runs on a record.</h2>
          </div>
          <p>
            The group chat is good for reminding people. It is a poor place to keep money.
            Chama Ledger gives every promise, payment and decision a line of its own.
          </p>
        </div>

        <div class="mkt-problems">
          <article>
            <h3>The chat scrolls. The record stays.</h3>
            <p>Every contribution is tied to a member, a date and an M-Pesa reference, so nobody has to reconstruct last month from a screenshot.</p>
          </article>
          <article>
            <h3>Loans need more than a promise.</h3>
            <p>Guarantors, repayment dates and balances sit together. The committee can see the full picture before it approves the next one.</p>
          </article>
          <article>
            <h3>AGMs should start with numbers.</h3>
            <p>Contributions, payouts and fines arrive already reconciled. Export the ledger when the meeting asks for proof.</p>
          </article>
        </div>
      </div>
    </section>

    <section class="mkt-section mkt-inside" id="inside">
      <div class="mkt-wrap">
        <div class="mkt-section-head">
          <div>
            <p class="mkt-kicker">One shared record</p>
            <h2>Everything the committee carries, in one place.</h2>
          </div>
          <p>Not another chat group. Not a treasurer's private spreadsheet. A working record for the money the chama already moves.</p>
        </div>

        <div class="mkt-inside-grid">
          <article class="mkt-feature">
            <div class="mkt-feature-top">
              <span class="mkt-feature-icon"><Icon name="transactions" size={21} /></span>
              <span class="mkt-feature-tag">The monthly run</span>
            </div>
            <h3>Close the contribution run before the meeting ends.</h3>
            <p>See who has paid, who is behind and which M-Pesa reference settles each line. No roll call required.</p>

            <div class="mkt-run-card" aria-label="Sample contribution run">
              <div class="mkt-run-head">
                <span>October contribution run</span>
                <strong>9 of 12 paid</strong>
              </div>
              <div class="mkt-run-row"><span>M. Wanjiku</span><span class="mkt-run-status">Paid</span></div>
              <div class="mkt-run-row"><span>J. Otieno</span><span class="mkt-run-status">Paid</span></div>
              <div class="mkt-run-row"><span>F. Achieng</span><span class="mkt-run-status mkt-run-late">Following up</span></div>
            </div>
          </article>

          <div class="mkt-modules">
            <article>
              <span class="mkt-module-icon"><Icon name="loans" size={19} /></span>
              <div><h3>Loans and guarantors</h3><p>Applications, approvals, guarantors and repayments in one timeline.</p></div>
            </article>
            <article>
              <span class="mkt-module-icon"><Icon name="welfare" size={19} /></span>
              <div><h3>Welfare claims</h3><p>Requests, committee decisions and payout records that stay with the fund.</p></div>
            </article>
            <article>
              <span class="mkt-module-icon"><Icon name="rotation" size={19} /></span>
              <div><h3>Rotation turns</h3><p>The merry-go-round order, proposals and payouts without a second notebook.</p></div>
            </article>
            <article>
              <span class="mkt-module-icon"><Icon name="fines" size={19} /></span>
              <div><h3>Fines and penalties</h3><p>Clear rules, recorded charges and a visible path to settling them.</p></div>
            </article>
            <article>
              <span class="mkt-module-icon"><Icon name="reports" size={19} /></span>
              <div><h3>Reports and exports</h3><p>CSV and PDF statements ready for the treasurer, the AGM or the auditor.</p></div>
            </article>
            <article>
              <span class="mkt-module-icon"><Icon name="audit" size={19} /></span>
              <div><h3>A readable audit trail</h3><p>Who changed what, when, and what it looked like before.</p></div>
            </article>
          </div>
        </div>
      </div>
    </section>

    <section class="mkt-section mkt-how" id="how">
      <div class="mkt-wrap">
        <div class="mkt-section-head mkt-section-head-dark">
          <div>
            <p class="mkt-kicker">From first meeting to first report</p>
            <h2>Set up the record in three moves.</h2>
          </div>
          <p>No new wallet. No member balances moved. Start with the chama you already have.</p>
        </div>

        <div class="mkt-steps">
          <article>
            <span class="mkt-step-label">First</span>
            <h3>Create the chama</h3>
            <p>Name it, set the contribution amount and frequency, and add the chama's own M-Pesa shortcode.</p>
          </article>
          <article>
            <span class="mkt-step-label">Second</span>
            <h3>Invite your people</h3>
            <p>Share one link. Each request comes to the committee, and an admin approves every new member.</p>
          </article>
          <article>
            <span class="mkt-step-label">Third</span>
            <h3>Keep the record</h3>
            <p>Record contributions, approve what needs a second pair of eyes, and export the statement when it is needed.</p>
          </article>
        </div>
      </div>
    </section>

    <section class="mkt-section mkt-committee" id="committee">
      <div class="mkt-wrap mkt-committee-grid">
        <div class="mkt-committee-copy">
          <p class="mkt-kicker">For the committee</p>
          <h2>Authority is clear. So is the record.</h2>
          <p>
            A chama works when everyone knows who can approve what. Roles in Chama Ledger follow
            that responsibility instead of putting every decision in one person's hands.
          </p>
          <a class="mkt-text-link" href={startHref}>Set up your committee <Icon name="arrow" size={15} /></a>
        </div>

        <div class="mkt-role-list">
          <article>
            <span class="mkt-role-tag">Admins</span>
            <div><h3>Guard the membership and the big decisions.</h3><p>Approve new members, loans, welfare claims and payouts. Sensitive entries can require a PIN.</p></div>
          </article>
          <article>
            <span class="mkt-role-tag">Treasurers</span>
            <div><h3>Keep the money record accurate.</h3><p>Record contributions and payments, reconcile the chama's shortcode and prepare the reports.</p></div>
          </article>
          <article>
            <span class="mkt-role-tag">Members</span>
            <div><h3>See where the chama stands.</h3><p>Check personal contributions, loans, welfare and rotation position without asking for a screenshot.</p></div>
          </article>
        </div>
      </div>
    </section>

    <section class="mkt-section mkt-safety">
      <div class="mkt-wrap mkt-safety-grid">
        <div class="mkt-safety-copy">
          <p class="mkt-kicker">The important boundary</p>
          <h2>Your money never passes through us.</h2>
          <p>
            Chama Ledger is the record, not the account. Contributions go directly to your chama's
            Paybill or Till. We do not hold, move or lend member funds.
          </p>
        </div>
        <div class="mkt-safety-points">
          <article><h3>The shortcode stays yours</h3><p>Members pay the chama the way they already do. The platform records what happened.</p></article>
          <article><h3>Approvals stay human</h3><p>The committee makes the decision. The ledger keeps the trail and the reason.</p></article>
          <article><h3>Records leave with you</h3><p>Download the transactions, reports and audit history whenever the chama needs them.</p></article>
          <article><h3>Each chama is separate</h3><p>Memberships, records and permissions are scoped to the chama they belong to.</p></article>
        </div>
      </div>
    </section>

    <section class="mkt-cta">
      <div class="mkt-wrap mkt-cta-inner">
        <div>
          <p class="mkt-kicker">Start with the record</p>
          <h2>Give the chama something better than a scroll-back.</h2>
          <p>Set up the ledger once. Let every meeting start from the same numbers.</p>
        </div>
        <div class="mkt-cta-actions">
          <a class="mkt-button mkt-button-lime" href={startHref}>{startLabel}<Icon name="arrow" size={17} /></a>
          {#if !signedIn}
            <a class="mkt-button mkt-button-outline" href="/login">I already have an account</a>
          {/if}
        </div>
      </div>
    </section>
  </main>

  <footer class="mkt-footer">
    <div class="mkt-wrap mkt-footer-top">
      <div class="mkt-footer-brand">
        <span class="mkt-brand-mark" aria-hidden="true"><i></i><i></i><i></i></span>
        <div><strong>{session.appName}</strong><p>A shared ledger for chamas that keep their own money.</p></div>
      </div>
      <nav class="mkt-footer-links" aria-label="Footer">
        <a href="#ledger">Why a ledger</a>
        <a href="#inside">What's inside</a>
        <a href="#how">How it works</a>
        <a href="/login">Sign in</a>
      </nav>
    </div>
    <div class="mkt-wrap mkt-footer-bottom">
      <span>© {new Date().getFullYear()} {session.appName}</span>
      <span>Records only. No wallet. No custody.</span>
    </div>
  </footer>
</div>
