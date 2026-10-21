const imageSignatures: Record<string, (bytes: Uint8Array) => boolean> = {
  'image/jpeg': bytes => bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff,
  'image/png': bytes => bytes.length >= 8
    && bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47
    && bytes[4] === 0x0d && bytes[5] === 0x0a && bytes[6] === 0x1a && bytes[7] === 0x0a,
  'image/webp': bytes => bytes.length >= 12
    && String.fromCharCode(...bytes.slice(0, 4)) === 'RIFF'
    && String.fromCharCode(...bytes.slice(8, 12)) === 'WEBP',
}

export async function validateNorthstarPhoto (file: File): Promise<string | null> {
  if (file.size === 0) return 'The selected image is empty. Choose a valid image file.'
  if (file.size > 1_000_000) return 'Choose an image smaller than 1 MB.'
  if (!file.type.startsWith('image/')) return 'Choose an image file.'

  const matchesSignature = imageSignatures[file.type]
  if (matchesSignature) {
    try {
      const bytes = new Uint8Array(await file.slice(0, 12).arrayBuffer())
      if (!matchesSignature(bytes)) return 'The selected file content does not match its image type.'
    } catch {
      return 'The selected image could not be validated. Choose another file.'
    }
  }

  // Decode the file as an image as an additional client-side validity check.
  // This does not replace server-side validation for direct Storage API calls.
  try {
    if (typeof createImageBitmap === 'function') {
      const bitmap = await createImageBitmap(file)
      const valid = bitmap.width > 0 && bitmap.height > 0
      bitmap.close()
      if (!valid) return 'The selected file is not a readable image.'
    } else {
      const objectUrl = URL.createObjectURL(file)
      const valid = await new Promise<boolean>(resolve => {
        const image = new Image()
        image.onload = () => resolve(image.naturalWidth > 0 && image.naturalHeight > 0)
        image.onerror = () => resolve(false)
        image.src = objectUrl
      })
      URL.revokeObjectURL(objectUrl)
      if (!valid) return 'The selected file is not a readable image.'
    }
  } catch {
    return 'The selected file is not a readable image.'
  }

  return null
}
