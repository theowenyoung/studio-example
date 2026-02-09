import { Layout } from '../components/Layout'
import type { Post } from '../db/posts'
import type { Context } from 'hono'

const List = (props: { post: Post }) => (
  <li>
    <a href={`/post/${props.post.id}`}>{props.post.title}</a>
  </li>
)

export const Top = (props: { posts: Post[]; c: Context }) => {
  return (
    <Layout title={'Top'} c={props.c}>
      <main>
        <h2>Posts</h2>
        <ul>
          {props.posts.map((post) => (
            <List post={post} />
          ))}
        </ul>
      </main>
    </Layout>
  )
}
