import { html } from "hono/html";
import type { Context } from "hono";

export const Layout = (props: {
  title: string;
  children?: any;
  c: Context;
}) => {
  return html`<!DOCTYPE html>
    <html>
      <head>
        <meta charset="UTF-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1.0" />
        <title>${props.title}</title>
        <link rel="stylesheet" href="/static/css/mini-default.min.css" />
        <link
          rel="stylesheet"
          href="${props.c.get("clientAsset")("index.css")}"
        />
      </head>
      <body style="padding: 1em 2em">
        <header>
          <h1>
            <a href="/">Hono Example</a>
          </h1>
        </header>
        ${props.children}
        <footer>
          <p>
            Built with love
            <a href="https://github.com/honojs/hono">Hono</a>
          </p>
        </footer>
        <script type="module" src="/static/js/datastar.js"></script>
      </body>
    </html>`;
};
