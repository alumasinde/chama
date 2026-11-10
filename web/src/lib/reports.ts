import { api, apiDownload } from './api';
import { session } from './session.svelte';
import type { ReportJob } from './types';

export async function exportReport(reportCode: string, format: 'csv' | 'pdf'): Promise<void> {
  if (!session.activeGroupId || !session.access) throw new Error('Select a chama first.');
  const job = await api<ReportJob>(`/groups/${session.activeGroupId}/reports/jobs`, {
    method: 'POST',
    auth: session.access,
    body: { report_code: reportCode, format },
  });
  await downloadJob(job);
}

export async function downloadJob(job: ReportJob): Promise<void> {
  if (!session.activeGroupId || !session.access) throw new Error('Select a chama first.');
  const blob = await apiDownload(
    `/groups/${session.activeGroupId}/reports/jobs/${job.id}/download`,
    session.access,
  );
  const link = document.createElement('a');
  link.href = URL.createObjectURL(blob);
  link.download = job.file_name || `${job.report_code}.${job.format}`;
  document.body.appendChild(link);
  link.click();
  link.remove();
  window.setTimeout(() => URL.revokeObjectURL(link.href), 1500);
}
