import PropTypes from 'prop-types'
import React from 'react'

import _ from 'intl'
import ActionButton from './action-button'
import Component from './base-component'
import Icon from 'icon'
import Tooltip from 'tooltip'
import { alert } from 'modal'
import { isAdmin } from 'selectors'
import { SelectVdi, SelectResourceSetsVdi } from './select-objects'
import { addSubscriptions, connectStore, resolveResourceSet } from './utils'
import { ejectCd, insertCd, subscribeResourceSets } from './xo'
import {
  createGetObjectsOfType,
  createFinder,
  createGetObject,
  createSelector,
} from './selectors'

@addSubscriptions({
  resourceSets: subscribeResourceSets,
})
@connectStore(() => {
  const getCdDrive = createFinder(
    createGetObjectsOfType('VBD').pick((_, { vm }) => vm.$VBDs),
    [vbd => vbd.is_cd_drive]
  )

  const getMountedIso = createGetObject((state, props) => {
    const cdDrive = getCdDrive(state, props)
    if (cdDrive) {
      return cdDrive.VDI
    }
  })

  return {
    cdDrive: getCdDrive,
    isAdmin,
    mountedIso: getMountedIso,
  }
})
export default class IsoDevice extends Component {
  static propTypes = {
    vm: PropTypes.object.isRequired,
  }

  _getPredicate = createSelector(
    () => this.props.vm.$pool,
    () => this.props.vm.$container,
    (vmPool, vmContainer) => sr => {
      const vmRunning = vmContainer !== vmPool
      const sameHost = vmContainer === sr.$container
      const samePool = vmPool === sr.$pool

      return (
        samePool &&
        (vmRunning ? sr.shared || sameHost : true) &&
        (sr.SR_type === 'iso' || (sr.SR_type === 'udev' && sr.size))
      )
    }
  )

  _getResolvedResourceSet = createSelector(
    createFinder(
      () => this.props.resourceSets,
      createSelector(
        () => this.props.vm.resourceSet,
        id => resourceSet => resourceSet.id === id
      )
    ),
    resolveResourceSet
  )

  _handleInsert = iso => {
    const { vm } = this.props

    if (iso) {
      insertCd(vm, iso.id, true)
    } else {
      ejectCd(vm)
    }
  }

  _handleEject = () => ejectCd(this.props.vm)

  _showWarning = () => alert(_('cdDriveNotInstalled'), _('cdDriveInstallation'))

  render() {
    const { cdDrive, isAdmin, mountedIso } = this.props
    const resourceSet = this._getResolvedResourceSet()
    const useResourceSet = !(isAdmin || resourceSet === undefined)
    const SelectVdi_ = useResourceSet ? SelectResourceSetsVdi : SelectVdi

    return (
      <div className='input-group'>
        <SelectVdi_
          onChange={this._handleInsert}
          resourceSet={useResourceSet ? resourceSet : undefined}
          srPredicate={this._getPredicate()}
          value={mountedIso}
        />
        <span className='input-group-btn'>
          <ActionButton
            disabled={!mountedIso}
            handler={this._handleEject}
            icon='vm-eject'
          />
        </span>
        {mountedIso && !cdDrive.device && (
          <Tooltip content={_('cdDriveNotInstalled')}>
            <a
              className='text-warning btn btn-link'
              onClick={this._showWarning}
            >
              <Icon icon='alarm' size='lg' />
            </a>
          </Tooltip>
        )}
      </div>
    )
  }
}
