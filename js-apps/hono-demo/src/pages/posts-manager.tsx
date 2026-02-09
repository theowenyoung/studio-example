import { html, raw } from 'hono/html'
import type { Post } from '../db/posts'
import type { Context } from 'hono'
import { Layout } from '../components/Layout'

export const PostsManager = (props: { posts: Post[]; c: Context }) => {
  const postsListHtml = props.posts.length === 0
    ? '<p>No posts yet. Create one above!</p>'
    : props.posts
        .map(
          (post) => {
            const escapedTitle = post.title.replace(/'/g, "\\'").replace(/"/g, '&quot;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
            const escapedBody = post.body.replace(/'/g, "\\'").replace(/"/g, '&quot;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
            const displayTitle = post.title.replace(/</g, '&lt;').replace(/>/g, '&gt;')
            const displayBody = post.body.replace(/</g, '&lt;').replace(/>/g, '&gt;')
            return `
              <article
                style="margin-bottom: 1.5em; padding: 1em; border: 1px solid #ddd; border-radius: 4px;"
                id="view-${post.id}"
              >
                <h4>${displayTitle}</h4>
                <p>${displayBody}</p>
                <small style="color: #666;">
                  Created: ${post.created_at ? new Date(post.created_at).toLocaleString() : 'N/A'}
                </small>
                <div style="margin-top: 1em;">
                  <button
                    onclick="document.getElementById('view-${post.id}').style.display='none'; document.getElementById('edit-${post.id}').style.display='block';"
                    style="margin-right: 0.5em;"
                  >
                    Edit
                  </button>
                  <form method="POST" action="/api/posts/${post.id}" style="display: inline;">
                    <input type="hidden" name="_method" value="DELETE" />
                    <button
                      type="submit"
                      onclick="return confirm('确定要删除这篇 post 吗？')"
                      style="background-color: #d9534f; color: white; border: none; padding: 0.25em 0.5em; cursor: pointer;"
                    >
                      Delete
                    </button>
                  </form>
                </div>
              </article>

              <article
                style="margin-bottom: 1.5em; padding: 1em; border: 2px solid #5cb85c; border-radius: 4px; background-color: #f9f9f9; display: none;"
                id="edit-${post.id}"
              >
                <h4>Editing Post</h4>
                <form method="POST" action="/api/posts/${post.id}">
                  <input type="hidden" name="_method" value="PUT" />
                  <div style="margin-bottom: 1em;">
                    <label>
                      Title:
                      <input
                        type="text"
                        name="title"
                        value="${displayTitle}"
                        required
                        style="width: 100%; margin-top: 0.5em;"
                      />
                    </label>
                  </div>
                  <div style="margin-bottom: 1em;">
                    <label>
                      Body:
                      <textarea
                        name="body"
                        required
                        rows="4"
                        style="width: 100%; margin-top: 0.5em;"
                      >${displayBody}</textarea>
                    </label>
                  </div>
                  <button type="submit" style="background-color: #5cb85c; color: white; margin-right: 0.5em; border: none; padding: 0.25em 0.5em; cursor: pointer;">
                    Save
                  </button>
                  <button
                    type="button"
                    onclick="document.getElementById('edit-${post.id}').style.display='none'; document.getElementById('view-${post.id}').style.display='block';"
                    style="background-color: #777; color: white; border: none; padding: 0.25em 0.5em; cursor: pointer;"
                  >
                    Cancel
                  </button>
                </form>
              </article>
            `
          }
        )
        .join('')

  const content = html`
    <nav style="margin-bottom: 1em;">
      <a href="/posts">Simple List</a>
    </nav>

    <main data-store='{"editingId":null,"editTitle":"","editBody":"","newTitle":"","newBody":""}'>
      <h2>Posts Manager with Datastar</h2>

      <!-- 创建新 Post 表单 -->
      <section style="margin-bottom: 2em; padding: 1em; border: 1px solid #ccc; border-radius: 4px;">
        <h3>Create New Post</h3>
        <form method="POST" action="/api/posts">
          <div style="margin-bottom: 1em;">
            <label>
              Title:
              <input
                type="text"
                name="title"
                required
                style="width: 100%; margin-top: 0.5em;"
              />
            </label>
          </div>
          <div style="margin-bottom: 1em;">
            <label>
              Body:
              <textarea
                name="body"
                required
                rows="4"
                style="width: 100%; margin-top: 0.5em;"
              ></textarea>
            </label>
          </div>
          <button type="submit">Create Post</button>
        </form>
      </section>

      <!-- Posts 列表 -->
      <section id="posts-list">
        <h3>All Posts</h3>
        <div id="posts-container">
          ${raw(postsListHtml)}
        </div>
      </section>
    </main>
  `

  return Layout({ title: 'Posts Manager', children: content, c: props.c })
}
