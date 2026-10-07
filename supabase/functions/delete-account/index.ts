import { withSupabase } from 'npm:@supabase/server@1'

async function collectFiles(
  storage: any,
  bucket: string,
  prefix: string,
): Promise<string[]> {
  const result: string[] = []
  let offset = 0

  while (true) {
    const { data, error } = await storage
      .from(bucket)
      .list(prefix, {
        limit: 100,
        offset,
        sortBy: { column: 'name', order: 'asc' },
      })

    if (error) throw error
    if (!data || data.length === 0) break

    for (const item of data) {
      const path = prefix ? `${prefix}/${item.name}` : item.name

      if (item.id == null) {
        result.push(...await collectFiles(storage, bucket, path))
      } else {
        result.push(path)
      }
    }

    if (data.length < 100) break
    offset += data.length
  }

  return result
}

async function removeUserFiles(
  storage: any,
  bucket: string,
  userId: string,
) {
  const files = await collectFiles(storage, bucket, userId)

  for (let i = 0; i < files.length; i += 100) {
    const chunk = files.slice(i, i + 100)
    if (chunk.length === 0) continue

    const { error } = await storage.from(bucket).remove(chunk)
    if (error) throw error
  }
}

export default {
  fetch: withSupabase({ auth: 'user' }, async (req, ctx) => {
    try {
      if (req.method !== 'POST') {
        return Response.json(
          { error: 'Method not allowed' },
          { status: 405 },
        )
      }

      const body = await req.json().catch(() => ({}))
      if (body?.confirm !== true) {
        return Response.json(
          { error: 'Confirmation is required' },
          { status: 400 },
        )
      }

      const userId = ctx.userClaims?.id
      if (!userId) {
        return Response.json(
          { error: 'Authenticated user not found' },
          { status: 401 },
        )
      }

      // Require a recently issued session for this destructive action.
      // The Flutter client re-authenticates with the current password first.
      const issuedAt = Number(ctx.jwtClaims?.iat ?? 0)
      const now = Math.floor(Date.now() / 1000)
      const sessionAge = now - issuedAt

      if (
        !Number.isFinite(issuedAt) ||
        issuedAt <= 0 ||
        sessionAge < -60 ||
        sessionAge > 300
      ) {
        return Response.json(
          { error: 'Recent authentication required' },
          { status: 401 },
        )
      }

      // User-owned objects use /<user-id>/... as their top-level prefix.
      for (const bucket of [
        'avatars',
        'rescue-verification',
        'chat-media',
      ]) {
        await removeUserFiles(
          ctx.supabaseAdmin.storage,
          bucket,
          userId,
        )
      }

      const { error } =
        await ctx.supabaseAdmin.auth.admin.deleteUser(userId)

      if (error) {
        console.error('deleteUser failed', error)
        return Response.json(
          { error: error.message },
          { status: 500 },
        )
      }

      return Response.json({
        ok: true,
        deleted_user_id: userId,
      })
    } catch (error) {
      console.error('delete-account failed', error)
      return Response.json(
        {
          error:
            error instanceof Error ? error.message : String(error),
        },
        { status: 500 },
      )
    }
  }),
}
