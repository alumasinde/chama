export class ApiFailure extends Error {
  status: number;
  code: string;
  fields?: Record<string, string>;

  constructor(status: number, code: string, message: string, fields?: Record<string, string>) {
    super(message);
    this.name = 'ApiFailure';
    this.status = status;
    this.code = code;
    this.fields = fields;
  }
}

type RequestOptions = {
  method?: string;
  body?: unknown;
  auth?: string | null;
  retry?: boolean;
  headers?: Record<string, string>;
};

let refreshHandler: (() => Promise<boolean>) | null = null;

export function setRefreshHandler(handler: () => Promise<boolean>) {
  refreshHandler = handler;
}

// api talks to /api/v1, refreshes once on a 401, and normalises errors.
export async function apiDownload(path: string, auth: string): Promise<Blob> {
  const load = async (retry: boolean): Promise<Response> => {
    const response = await fetch(`/api/v1${path}`, { headers: { Authorization: `Bearer ${auth}` } });
    if (response.status === 401 && retry && refreshHandler && (await refreshHandler())) {
      return load(false);
    }
    return response;
  };
  const response = await load(true);
  if (!response.ok) {
    const text = await response.text();
    let message = 'Could not download that file.';
    try {
      message = JSON.parse(text)?.error?.message ?? message;
    } catch {
      // Keep the plain fallback when the server did not return JSON.
    }
    throw new ApiFailure(response.status, 'download_failed', message);
  }
  return response.blob();
}

export async function api<T>(path: string, options: RequestOptions = {}): Promise<T> {
  const headers: Record<string, string> = { ...options.headers };
  if (options.body !== undefined) headers['Content-Type'] = 'application/json';
  if (options.auth) headers.Authorization = `Bearer ${options.auth}`;

  const response = await fetch(`/api/v1${path}`, {
    method: options.method ?? 'GET',
    headers,
    body: options.body === undefined ? undefined : JSON.stringify(options.body),
  });

  if (response.status === 401 && options.auth && options.retry !== false && refreshHandler) {
    if (await refreshHandler()) return api<T>(path, { ...options, retry: false });
  }
  if (response.status === 204) return undefined as T;

  const text = await response.text();
  const payload = text ? JSON.parse(text) : null;
  if (!response.ok) {
    const body = payload?.error ?? {};
    throw new ApiFailure(
      response.status,
      body.code ?? 'request_failed',
      body.message ?? 'Something went wrong. Try again.',
      body.fields,
    );
  }
  return payload as T;
}
