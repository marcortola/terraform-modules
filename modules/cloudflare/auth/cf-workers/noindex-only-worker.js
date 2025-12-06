addEventListener('fetch', event => {
    event.respondWith(handleRequest(event.request));
});

async function handleRequest(request) {
    const originalResponse = await fetch(request);

    const newResponse = new Response(originalResponse.body, originalResponse);
    newResponse.headers.set('X-Robots-Tag', 'noindex, nofollow');

    return newResponse;
}
