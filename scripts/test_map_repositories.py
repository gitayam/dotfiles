"""Repository map: remote cleaning, heading extraction and the write boundaries."""
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import map_work_repositories as mapper

ROOT=Path(__file__).resolve().parents[1]


def make_repo(base,name,url,readme=True):
    """A real git checkout with an origin under base; no working tree is needed."""
    path=base/name;path.mkdir(parents=True)
    (path/'.git').mkdir()
    (path/'README.md').write_text(f'# {name}\n')
    if url is not None:
        subprocess.run(['git','-C',str(path),'init','--quiet'],check=True)
        subprocess.run(['git','-C',str(path),'config','remote.origin.url',url],check=True)
    return path


class RemoteName(unittest.TestCase):
    def test_plain_urls_collapse_to_host_owner_name(self):
        self.assertEqual(mapper.remote_name('https://github.com/owner/repo.git'),'github.com/owner/repo')
        self.assertEqual(mapper.remote_name('git@github.com:owner/repo.git'),'github.com/owner/repo')
        self.assertEqual(mapper.remote_name('ssh://git@host:2222/owner/repo'),'host:2222/owner/repo')

    def test_no_credential_user_host_or_query_survives(self):
        shown=mapper.remote_name('https://user:pass@github.com/owner/repo')
        self.assertEqual(shown,'github.com/owner/repo')
        self.assertNotIn('user:pass',shown)
        query=mapper.remote_name('https://github.com/owner/repo?token=secret')
        self.assertEqual(query,'github.com/owner/repo')
        self.assertNotIn('token',query)
        self.assertEqual(mapper.remote_name('file:///some/local/path'),'(local path)')
        self.assertEqual(mapper.remote_name('/bare/local/path'),'(local path)')
        self.assertIsNone(mapper.remote_name('  '))

    def test_first_line_prefers_a_heading_and_caps_at_100(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'doc.md';path.write_text('intro\n\n# The Heading\nbody\n')
            self.assertEqual(mapper.first_line(path),'The Heading')
            path.write_text('# '+'x'*200+'\n')
            self.assertEqual(len(mapper.first_line(path)),100)
            self.assertIsNone(mapper.first_line(Path(tmp)/'missing.md'))


class Map(unittest.TestCase):
    def setUp(self):
        self._tmp=tempfile.TemporaryDirectory();self.base=Path(self._tmp.name).resolve()
        self.addCleanup(self._tmp.cleanup)

    def run_map(self,*args,cwd=None):
        return subprocess.run([sys.executable,str(ROOT/'scripts/map_work_repositories.py'),*args],
                              capture_output=True,text=True,cwd=cwd)

    def test_dry_run_is_the_default_and_writes_nothing(self):
        repo=make_repo(self.base,'repo','https://github.com/owner/repo')
        target=self.base/'map.md'
        out=self.run_map('--root',f'r={self.base}','--output',str(target),'--date','2026-11-20')
        self.assertEqual(out.returncode,0,out.stderr)
        self.assertIn('1 listed',out.stdout)
        self.assertFalse(target.exists(),'the dry run wrote the map')

    def test_apply_writes_outside_checkouts_and_refuses_inside_one(self):
        repo=make_repo(self.base,'repo','https://github.com/owner/repo')
        outside=self.base/'map.md'
        out=self.run_map('--root',f'r={self.base}','--output',str(outside),'--date','2026-11-20','--apply')
        self.assertEqual(out.returncode,0,out.stderr)
        text=outside.read_text()
        self.assertIn('github.com/owner/repo',text)
        self.assertNotIn('https://',text)
        inside=repo/'map.md'
        out=self.run_map('--root',f'r={self.base}','--output',str(inside),'--date','2026-11-20','--apply')
        self.assertNotEqual(out.returncode,0)
        self.assertIn('outside every checkout',out.stderr)
        self.assertFalse(inside.exists())

    def test_a_secrets_folder_is_never_listed(self):
        repo=make_repo(self.base,'repo','https://github.com/owner/repo')
        secrets=repo/'secrets';secrets.mkdir();(secrets/'.git').mkdir()
        out=self.run_map('--root',f'r={self.base}','--output',str(self.base/'map.md'),'--date','2026-11-20')
        self.assertEqual(out.returncode,0,out.stderr)
        self.assertNotIn('secrets',out.stdout)

    def test_a_linked_worktree_is_counted_and_only_listed_when_asked(self):
        repo=make_repo(self.base,'repo','https://github.com/owner/repo')
        wt=self.base/'wt';wt.mkdir();(wt/'.git').write_text('')
        out=self.run_map('--root',f'r={self.base}','--output',str(self.base/'map.md'),'--date','2026-11-20')
        self.assertEqual(out.returncode,0,out.stderr)
        self.assertNotIn('wt',out.stdout)
        self.assertIn('1 linked worktree',out.stdout)
        out=self.run_map('--root',f'r={self.base}','--output',str(self.base/'map.md'),
                         '--date','2026-11-20','--include-worktrees')
        self.assertIn('worktree',out.stdout)
        self.assertIn('wt',out.stdout)

    def test_draft_directions_are_listed_but_never_read(self):
        make_repo(self.base,'repo','https://github.com/owner/repo')
        drafts=self.base/'drafts';drafts.mkdir()
        (drafts/'repo.md').write_text('IGNORED')
        out=self.run_map('--root',f'r={self.base}','--output',str(self.base/'map.md'),
                         '--date','2026-11-20','--drafts',str(drafts))
        self.assertEqual(out.returncode,0,out.stderr)
        self.assertIn('drafts/repo.md',out.stdout.replace('\\','/'))
        self.assertNotIn('IGNORED',out.stdout)


if __name__=='__main__':
    unittest.main()
