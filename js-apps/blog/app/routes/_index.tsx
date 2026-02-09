import { CounterButton } from "@repo/ui/counter-button";
import { Link } from "@repo/ui/link";

export default function Index() {
  return (
    <div className="container">
      <h1 className="title">
        Blog <br />
        <span>Kitchen Sink</span>
      </h1>
      <CounterButton />
      <p className="description">
        Built With Studio {" & "}
        <Link href="https://remix.run/">Remix</Link>
      </p>
    </div>
  );
}
