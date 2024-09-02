#!/usr/bin/ruby -w
#
#   Author: Rohith
#   Date: 2013-04-24 13:57:18 +0100 (Wed, 24 Apr 2013)
#  $LastChangedBy$
#  $LastChangedDate$
#  $Revision$
#  $URL$
#  $Id$
#
#  vim:ts=4:sw=4:et

module Git

  def Git.get_current_branch

    current_branch=%x( git branch | awk '/^\*/ { print $2 }' 2>/dev/null )
    raise "unable to get the current git branch" unless $? == 0
    return current_branch.strip

  end

  # desc: gets a list of branches
  def Git.get_branches

    branches = %x( git branch | awk '{ print $2 }' )
    raise "unable to get a list of branches in repo, error $!" unless $? == 0
    return branches

  end

  def Git.checkout_branch( branch )

     current_branch = get_current_branch
     %x( git checkout #{branch} >/dev/null 2>&1 )
     raise "unable to checkout branch #{branch} output: #{output}" unless $? == 0
     # check we are in the correct branch
     current_branch = get_current_branch
     raise "unable to change into production branch #{branch}" unless /^#{branch}$/ =~ current_branch
     Log.debug( "switched from former branch #{current_branch} to current branch #{branch}" )

  end

  def Git.is_branch( branch )

     # get the current branch
     current_branch = get_current_branch
     Log.debug( "currently in # => {current_branch} branch" )
     return true if /^#{branch}$/ =~ current_branch 
     return false

  end

  # check the repo has the following commit id
  # @params
  # 	commitid		
  def Git.has_commit( commitid )

    Log.debug( "looking for commit id #{commitid} in branch " << get_current_branch )
    raise "you have not passed a commit id to look up" unless commitid
    %x( git show #{commitid} >/dev/null 2>&1 )
    return ( $? == 0 ) ? true : false
  	
  end

  # desc: get a list of files have have been changed from commit id's from and to
  def Git.files_changed( from, to )

    raise "you have not passwd a valid from commit id" unless from or has_commit( from )
    raise "you have not passed a valid to commit id" unless to or has_commit( to )
    Log.debug( "checking the files which have chnages from #{from} to #{to}" )
    changes = %x( git diff #{from}...#{to} --name-only ).split
    raise "unable to get the files that have changes, error $!" unless $? == 0
    Log.debug( "chnages between commits are #{changes}" )
    return changes

  end

end
