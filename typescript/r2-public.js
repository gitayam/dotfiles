/**
 * Cloudflare Worker to serve R2 files publicly
 * Deploy this as a separate worker for public file access
 */

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const key = url.pathname.slice(1); // Remove leading slash

    if (!key) {
      return new Response('Public File Server\n\nUsage: /' + 'filename.ext', {
        headers: { 'Content-Type': 'text/plain' }
      });
    }

    // Try to get file from R2 bucket
    const object = await env.FILES_BUCKET.get(key);
    
    if (!object) {
      return new Response('File not found', { status: 404 });
    }

    // Return the file with appropriate headers
    const headers = new Headers();
    object.writeHttpMetadata(headers);
    headers.set('Cache-Control', 'public, max-age=3600');
    
    return new Response(object.body, { headers });
  }
}