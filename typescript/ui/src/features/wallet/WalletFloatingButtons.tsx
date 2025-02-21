import { HistoryIcon, IconButton } from '@hyperlane-xyz/widgets';
import { Color } from '../../styles/Color';
import { useStore } from '../store';

export function WalletFloatingButtons() {
  const { setIsSideBarOpen, isSideBarOpen } = useStore((s) => ({
    setIsSideBarOpen: s.setIsSideBarOpen,
    isSideBarOpen: s.isSideBarOpen,
  }));

  return (
    <div className="absolute -top-8 right-0 flex-col items-center justify-end gap-4 sm:-right-8 sm:top-2 sm:flex">
      <IconButton
        className={`p-0.5 ${styles.roundedCircle} `}
        title="History"
        onClick={() => setIsSideBarOpen(!isSideBarOpen)}
      >
        <HistoryIcon color={Color.primary} height={20} width={20} />
      </IconButton>
      {/* <Link
        href={links.warpDocs}
        target="_blank"
        className={`p-0.5 ${styles.roundedCircle} ${styles.link}`}
      >
        <DocsIcon color={Color.primary} height={19} width={19} className="p-px" />
      </Link> */}
    </div>
  );
}

const styles = {
  link: 'hover:opacity-70 active:opacity-60',
  roundedCircle: 'rounded-full bg-white',
};
