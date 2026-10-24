// Sends the pending alerts in the outbox as emails. Called by the database
// whenever a new alert is queued, and by the back office "Send now" button.
// Needs the secrets NOTIFY_SECRET and RESEND_API_KEY. Without a mail key it
// leaves the alerts pending so nothing is lost.
import { createClient } from 'npm:@supabase/supabase-js@2';

const esc = (s: string) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

Deno.serve(async (req) => {
  if (req.headers.get('x-notify-secret') !== Deno.env.get('NOTIFY_SECRET')) {
    return new Response('not allowed', { status: 401 });
  }
  const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  const key = Deno.env.get('RESEND_API_KEY');
  const { data: rows, error } = await db.from('outbox').select('*').eq('status', 'pending').order('id').limit(25);
  if (error) return new Response(error.message, { status: 500 });
  if (!key) return new Response(JSON.stringify({ waiting: rows?.length ?? 0, note: 'no mail key set' }), { status: 200 });

  let sent = 0;
  for (const r of rows ?? []) {
    if (!r.to_email) {
      await db.from('outbox').update({ status: 'failed', error: 'no address set' }).eq('id', r.id);
      continue;
    }
    let link = '';
    if (r.link_bucket && r.link_path) {
      // A private link that stops working after 7 days. The video is never attached.
      const s = await db.storage.from(r.link_bucket).createSignedUrl(r.link_path, 60 * 60 * 24 * 7);
      if (s.data?.signedUrl) link = s.data.signedUrl;
    }
    const html = `<div style="font-family:system-ui,sans-serif;max-width:560px">
      <h2 style="margin:0 0 12px">${esc(r.subject)}</h2>
      <pre style="white-space:pre-wrap;font:inherit">${esc(r.body)}</pre>
      ${link ? `<p><a href="${link}" style="background:#0b0b0c;color:#fff;padding:12px 18px;border-radius:10px;text-decoration:none">Watch the video</a><br><small>This private link works for 7 days.</small></p>` : ''}
      <hr><small>Nolifa. This is an automatic alert.</small></div>`;
    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ from: Deno.env.get('NOTIFY_FROM') ?? 'Nolifa <onboarding@resend.dev>', to: [r.to_email], subject: r.subject, html }),
    });
    if (res.ok) {
      sent++;
      // A sign-in code is wiped the moment it has been sent.
      await db.from('outbox').update({
        status: 'sent', sent_at: new Date().toISOString(), error: null,
        ...(r.kind === 'login_code' ? { body: '(code removed after sending)' } : {}),
      }).eq('id', r.id);
    } else {
      await db.from('outbox').update({
        status: 'failed', error: (await res.text()).slice(0, 300),
        ...(r.kind === 'login_code' ? { body: '(code removed)' } : {}),
      }).eq('id', r.id);
    }
  }
  return new Response(JSON.stringify({ sent, tried: rows?.length ?? 0 }), { status: 200 });
});
