import { error } from '@sveltejs/kit';
import { CLIENTS, guide } from '$lib/connect';

export const prerender = true;
export const entries = () => CLIENTS.map((c) => ({ client: c.id }));

export function load({ params }) {
  const client = guide(params.client);
  if (!client) error(404, 'No such client');
  return { client };
}
