export function publicStorageUrl(baseUrl, bucket, objectPath) {
  const base = baseUrl.replace(/\/+$/, "");
  const encodedPath = objectPath
    .split("/")
    .map((segment) => encodeURIComponent(segment))
    .join("/");
  return `${base}/storage/v1/object/public/${bucket}/${encodedPath}`;
}

export function isOwnedPublicStorageUrl(
  value,
  { baseUrl, bucket, userId }
) {
  if (typeof value !== "string" || !baseUrl) return false;
  try {
    const url = new URL(value);
    const base = new URL(baseUrl);
    const prefix = `/storage/v1/object/public/${bucket}/${userId}/`;
    return (
      url.origin === base.origin &&
      url.pathname.startsWith(prefix) &&
      url.pathname.length > prefix.length
    );
  } catch {
    return false;
  }
}
